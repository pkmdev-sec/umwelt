#!/usr/bin/env bash
# ============================================================================
# config.sh — Configuration system with cascading priority
# ============================================================================
# Purpose: Loads and merges configuration from multiple sources following
#          precedence: defaults → global → workspace → project → env vars.
#          Provides config access, caching utilities, and JSON helpers.
#
# Usage: source lib/config.sh (auto-loads on source)
#        Access via: $UMWELT_* variables, cache_get/set/invalidate,
#                    json_escape_string, show_config
#
# Dependencies: bash 3.2+, jq (optional, falls back to python3), md5/md5sum
#
# Output: Exports UMWELT_* environment variables with merged configuration.
#         Config files: ~/.claude/umwelt.conf, .umweltrc, .umwelt/config
# ============================================================================
set -euo pipefail

# ─── Config Defaults ────────────────────────────────────────────
# Every configurable value with its default
UMWELT_CONFIG_LOADED="${UMWELT_CONFIG_LOADED:-0}"

# Scan/display limits
UMWELT_SCAN_DEPTH="${UMWELT_SCAN_DEPTH:-4}"
UMWELT_GIT_LOG_COUNT="${UMWELT_GIT_LOG_COUNT:-5}"
UMWELT_DIFF_MAX_LINES="${UMWELT_DIFF_MAX_LINES:-100}"
UMWELT_DOCKER_LOG_LINES="${UMWELT_DOCKER_LOG_LINES:-10}"
UMWELT_HOOK_TIMEOUT="${UMWELT_HOOK_TIMEOUT:-30}"

# Output format: text (default) or json
UMWELT_OUTPUT_FORMAT="${UMWELT_OUTPUT_FORMAT:-text}"

# Caching
UMWELT_CACHE_ENABLED="${UMWELT_CACHE_ENABLED:-1}"
UMWELT_CACHE_TTL="${UMWELT_CACHE_TTL:-300}"  # seconds (5 min default)
UMWELT_CACHE_DIR="${UMWELT_CACHE_DIR:-$HOME/.claude/.bang-cache}"

# Parallel execution
UMWELT_PARALLEL="${UMWELT_PARALLEL:-1}"
UMWELT_PARALLEL_JOBS="${UMWELT_PARALLEL_JOBS:-4}"

# File extensions for project-summary
UMWELT_FILE_EXTENSIONS="${UMWELT_FILE_EXTENSIONS:-ts tsx js jsx py rs go swift java kt rb php css scss html md json yaml yml toml}"

# Port scanning for api-health
UMWELT_LOCAL_PORTS="${UMWELT_LOCAL_PORTS:-3000:dev-server 3001:dev-alt 4000:graphql 5000:flask 5173:vite 5432:postgres 6379:redis 8000:uvicorn 8080:proxy 8443:https-alt 9090:prometheus 27017:mongodb}"

# Exclude patterns for find operations
UMWELT_EXCLUDE_DIRS="${UMWELT_EXCLUDE_DIRS:-node_modules .git dist build .next .nuxt target __pycache__ .pytest_cache coverage .mypy_cache Library}"

# ─── Config File Parser ─────────────────────────────────────────
# Parse a .umweltrc or umwelt.conf file (KEY=VALUE format, # comments)
parse_config_file() {
  local file="$1"
  if [ ! -f "$file" ]; then return 0; fi

  while IFS= read -r line || [ -n "$line" ]; do
    # Skip comments and blank lines
    line=$(echo "$line" | sed 's/#.*//' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    if [ -z "$line" ]; then continue; fi

    # Parse KEY=VALUE (support quoted values)
    local key value
    key=$(echo "$line" | cut -d'=' -f1 | tr -d ' ')
    value=$(echo "$line" | cut -d'=' -f2- | sed 's/^[[:space:]]*//' | sed 's/^"//' | sed 's/"$//' | sed "s/^'//" | sed "s/'$//")

    # Only set UMWELT_* variables (safety)
    case "$key" in
      UMWELT_*)
        export "$key=$value"
        ;;
    esac
  done < "$file"
}

# ─── Load Configuration (merge order) ──────────────────────────
load_config() {
  if [ "$UMWELT_CONFIG_LOADED" = "1" ]; then return 0; fi

  # 1. Defaults (already set above)

  # 2. Global config
  parse_config_file "$HOME/.claude/umwelt.conf"

  # 3. Workspace config (if in a .claude workspace)
  local workspace_config="$HOME/.claude/umwelt/.umweltrc"
  parse_config_file "$workspace_config"

  # 4. Project config (walk up from CWD)
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/.umweltrc" ]; then
      parse_config_file "$dir/.umweltrc"
      break
    elif [ -f "$dir/.umwelt/config" ]; then
      parse_config_file "$dir/.umwelt/config"
      break
    fi
    dir=$(dirname "$dir")
  done

  # 5. Environment variables override everything (already in effect)

  # Build exclude pattern for find
  UMWELT_FIND_EXCLUDE=""
  for d in $UMWELT_EXCLUDE_DIRS; do
    UMWELT_FIND_EXCLUDE="$UMWELT_FIND_EXCLUDE -not -path '*/${d}/*'"
  done
  export UMWELT_FIND_EXCLUDE

  export UMWELT_CONFIG_LOADED=1
}

# ─── Cache System ───────────────────────────────────────────────
cache_init() {
  if [ "$UMWELT_CACHE_ENABLED" != "1" ]; then return 0; fi
  mkdir -p "$UMWELT_CACHE_DIR" 2>/dev/null || {
    echo "Error: Failed to create cache directory: $UMWELT_CACHE_DIR" >&2
    return 1
  }
}

# Generate a cache key from loader name + arguments + project context
cache_key() {
  local loader="${1:-}"
  if [ -z "$loader" ]; then
    echo "error_no_loader"
    return 1
  fi
  shift
  local args="$*"
  local project_hash
  project_hash=$(echo "$PWD" | md5sum 2>/dev/null | cut -d' ' -f1 || echo "$PWD" | md5 2>/dev/null || echo "nohash")
  echo "${loader}_${project_hash}_$(echo "$args" | tr ' ' '_')"
}

# Get cached result (returns 1 if miss or expired)
cache_get() {
  if [ "$UMWELT_CACHE_ENABLED" != "1" ]; then return 1; fi

  local key="${1:-}"
  if [ -z "$key" ]; then
    return 1
  fi

  local cache_file="$UMWELT_CACHE_DIR/$key"

  if [ ! -f "$cache_file" ]; then return 1; fi

  # Check TTL
  local now file_age
  now=$(date +%s 2>/dev/null || echo 0)
  if stat -f '%m' /dev/null &>/dev/null 2>&1; then
    # macOS
    file_age=$(stat -f '%m' "$cache_file" 2>/dev/null || echo 0)
  else
    # Linux
    file_age=$(stat -c '%Y' "$cache_file" 2>/dev/null || echo 0)
  fi

  # Validate numeric values
  if ! [[ "$now" =~ ^[0-9]+$ ]]; then
    now=0
  fi
  if ! [[ "$file_age" =~ ^[0-9]+$ ]]; then
    file_age=0
  fi

  local ttl="${UMWELT_CACHE_TTL:-300}"
  if ! [[ "$ttl" =~ ^[0-9]+$ ]]; then
    ttl=300
  fi

  local age=$((now - file_age))
  if [ "$age" -gt "$ttl" ]; then
    rm -f "$cache_file" 2>/dev/null || true
    return 1
  fi

  cat "$cache_file" 2>/dev/null || return 1
  return 0
}

# Store result in cache
cache_set() {
  if [ "$UMWELT_CACHE_ENABLED" != "1" ]; then return 0; fi

  local key="${1:-}"
  local value="${2:-}"

  if [ -z "$key" ]; then
    return 1
  fi

  # Ensure cache directory exists
  if [ ! -d "$UMWELT_CACHE_DIR" ]; then
    mkdir -p "$UMWELT_CACHE_DIR" 2>/dev/null || return 1
  fi

  local cache_file="$UMWELT_CACHE_DIR/$key"
  echo "$value" > "$cache_file" 2>/dev/null || {
    echo "Error: Failed to write cache file: $cache_file" >&2
    return 1
  }
}

# Invalidate cache for a loader
cache_invalidate() {
  local loader="${1:-}"
  if [ -z "$loader" ]; then
    return 1
  fi
  if [ -d "$UMWELT_CACHE_DIR" ]; then
    rm -f "$UMWELT_CACHE_DIR/${loader}_"* 2>/dev/null || true
  fi
}

# Clear all cache
cache_clear() {
  rm -rf "${UMWELT_CACHE_DIR:?}"/* 2>/dev/null || true
}

# ─── jq Availability Check ──────────────────────────────────────
# Check if jq is available, use python3 as fallback
HAS_JQ=false
if command -v jq &>/dev/null; then
  HAS_JQ=true
fi

# JSON escape string helper
json_escape_string() {
  local value="$1"
  if [ "$HAS_JQ" = "true" ]; then
    echo "$value" | jq -R -s '.'
  else
    echo "$value" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))" 2>/dev/null || echo "\"$value\""
  fi
}

# Parse JSON from file
json_parse() {
  local file="$1"
  local query="${2:-.}"
  if [ "$HAS_JQ" = "true" ]; then
    jq -r "$query" "$file" 2>/dev/null || echo ""
  else
    python3 -c "import json; d=json.load(open('$file')); print($query)" 2>/dev/null || echo ""
  fi
}

# ─── JSON Output Helpers ────────────────────────────────────────
# Start a JSON object
json_start() {
  echo "{"
}

json_end() {
  echo "}"
}

# Add a JSON key-value pair (string)
json_kv() {
  local key="$1"
  local value="$2"
  local comma="${3:-,}"
  # Escape special JSON characters
  value=$(json_escape_string "$value")
  echo "  \"$key\": $value${comma}"
}

# Add a JSON key-value pair (number)
json_kvn() {
  local key="$1"
  local value="$2"
  local comma="${3:-,}"
  echo "  \"$key\": ${value}${comma}"
}

# Add a JSON key-value pair (boolean)
json_kvb() {
  local key="$1"
  local value="$2"
  local comma="${3:-,}"
  echo "  \"$key\": ${value}${comma}"
}

# Add a JSON key-array pair
json_kva() {
  local key="$1"
  local values="$2"
  local comma="${3:-,}"
  echo "  \"$key\": [${values}]${comma}"
}

# ─── Show Config ────────────────────────────────────────────────
show_config() {
  load_config
  echo "umwelt configuration"
  echo "════════════════════════════════════════"
  echo ""
  echo "Scan/Display:"
  echo "  UMWELT_SCAN_DEPTH=$UMWELT_SCAN_DEPTH"
  echo "  UMWELT_GIT_LOG_COUNT=$UMWELT_GIT_LOG_COUNT"
  echo "  UMWELT_DIFF_MAX_LINES=$UMWELT_DIFF_MAX_LINES"
  echo "  UMWELT_DOCKER_LOG_LINES=$UMWELT_DOCKER_LOG_LINES"
  echo "  UMWELT_HOOK_TIMEOUT=$UMWELT_HOOK_TIMEOUT"
  echo ""
  echo "Output:"
  echo "  UMWELT_OUTPUT_FORMAT=$UMWELT_OUTPUT_FORMAT"
  echo ""
  echo "Cache:"
  echo "  UMWELT_CACHE_ENABLED=$UMWELT_CACHE_ENABLED"
  echo "  UMWELT_CACHE_TTL=${UMWELT_CACHE_TTL}s"
  echo "  UMWELT_CACHE_DIR=$UMWELT_CACHE_DIR"
  echo ""
  echo "Parallel:"
  echo "  UMWELT_PARALLEL=$UMWELT_PARALLEL"
  echo "  UMWELT_PARALLEL_JOBS=$UMWELT_PARALLEL_JOBS"
  echo ""
  echo "Config files loaded (in order):"
  echo "  1. defaults (built-in)"
  [ -f "$HOME/.claude/umwelt.conf" ] && echo "  2. $HOME/.claude/umwelt.conf" || echo "  2. $HOME/.claude/umwelt.conf (not found)"
  [ -f "$HOME/.claude/umwelt/.umweltrc" ] && echo "  3. $HOME/.claude/umwelt/.umweltrc" || echo "  3. workspace .umweltrc (not found)"

  local dir="$PWD"
  local found_project=0
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/.umweltrc" ]; then
      echo "  4. $dir/.umweltrc"
      found_project=1
      break
    elif [ -f "$dir/.umwelt/config" ]; then
      echo "  4. $dir/.umwelt/config"
      found_project=1
      break
    fi
    dir=$(dirname "$dir")
  done
  if [ "$found_project" -eq 0 ]; then
    echo "  4. project config (not found)"
  fi
}

# Auto-load config when sourced
load_config
cache_init
