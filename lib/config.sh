#!/usr/bin/env bash
# bang-framework: Configuration system
# Merges defaults → global → workspace → project configs
# Config files: ~/.claude/bang.conf, .bangrc, .bang/config
set -euo pipefail

# ─── Config Defaults ────────────────────────────────────────────
# Every configurable value with its default
BANG_CONFIG_LOADED="${BANG_CONFIG_LOADED:-0}"

# Scan/display limits
BANG_SCAN_DEPTH="${BANG_SCAN_DEPTH:-4}"
BANG_GIT_LOG_COUNT="${BANG_GIT_LOG_COUNT:-5}"
BANG_DIFF_MAX_LINES="${BANG_DIFF_MAX_LINES:-100}"
BANG_DOCKER_LOG_LINES="${BANG_DOCKER_LOG_LINES:-10}"
BANG_HOOK_TIMEOUT="${BANG_HOOK_TIMEOUT:-30}"

# Output format: text (default) or json
BANG_OUTPUT_FORMAT="${BANG_OUTPUT_FORMAT:-text}"

# Caching
BANG_CACHE_ENABLED="${BANG_CACHE_ENABLED:-1}"
BANG_CACHE_TTL="${BANG_CACHE_TTL:-300}"  # seconds (5 min default)
BANG_CACHE_DIR="${BANG_CACHE_DIR:-$HOME/.claude/.bang-cache}"

# Parallel execution
BANG_PARALLEL="${BANG_PARALLEL:-1}"
BANG_PARALLEL_JOBS="${BANG_PARALLEL_JOBS:-4}"

# File extensions for project-summary
BANG_FILE_EXTENSIONS="${BANG_FILE_EXTENSIONS:-ts tsx js jsx py rs go swift java kt rb php css scss html md json yaml yml toml}"

# Port scanning for api-health
BANG_LOCAL_PORTS="${BANG_LOCAL_PORTS:-3000:dev-server 3001:dev-alt 4000:graphql 5000:flask 5173:vite 5432:postgres 6379:redis 8000:uvicorn 8080:proxy 8443:https-alt 9090:prometheus 27017:mongodb}"

# Exclude patterns for find operations
BANG_EXCLUDE_DIRS="${BANG_EXCLUDE_DIRS:-node_modules .git dist build .next .nuxt target __pycache__ .pytest_cache coverage .mypy_cache Library}"

# ─── Config File Parser ─────────────────────────────────────────
# Parse a .bangrc or bang.conf file (KEY=VALUE format, # comments)
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

    # Only set BANG_* variables (safety)
    case "$key" in
      BANG_*)
        export "$key=$value"
        ;;
    esac
  done < "$file"
}

# ─── Load Configuration (merge order) ──────────────────────────
load_config() {
  if [ "$BANG_CONFIG_LOADED" = "1" ]; then return 0; fi

  # 1. Defaults (already set above)

  # 2. Global config
  parse_config_file "$HOME/.claude/bang.conf"

  # 3. Workspace config (if in a .claude workspace)
  local workspace_config="$HOME/.claude/bang-framework/.bangrc"
  parse_config_file "$workspace_config"

  # 4. Project config (walk up from CWD)
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/.bangrc" ]; then
      parse_config_file "$dir/.bangrc"
      break
    elif [ -f "$dir/.bang/config" ]; then
      parse_config_file "$dir/.bang/config"
      break
    fi
    dir=$(dirname "$dir")
  done

  # 5. Environment variables override everything (already in effect)

  # Build exclude pattern for find
  BANG_FIND_EXCLUDE=""
  for d in $BANG_EXCLUDE_DIRS; do
    BANG_FIND_EXCLUDE="$BANG_FIND_EXCLUDE -not -path '*/${d}/*'"
  done
  export BANG_FIND_EXCLUDE

  export BANG_CONFIG_LOADED=1
}

# ─── Cache System ───────────────────────────────────────────────
cache_init() {
  if [ "$BANG_CACHE_ENABLED" != "1" ]; then return 0; fi
  mkdir -p "$BANG_CACHE_DIR"
}

# Generate a cache key from loader name + arguments + project context
cache_key() {
  local loader="$1"
  shift
  local args="$*"
  local project_hash
  project_hash=$(echo "$PWD" | md5sum 2>/dev/null | cut -d' ' -f1 || echo "$PWD" | md5 2>/dev/null || echo "nohash")
  echo "${loader}_${project_hash}_$(echo "$args" | tr ' ' '_')"
}

# Get cached result (returns 1 if miss or expired)
cache_get() {
  if [ "$BANG_CACHE_ENABLED" != "1" ]; then return 1; fi

  local key="$1"
  local cache_file="$BANG_CACHE_DIR/$key"

  if [ ! -f "$cache_file" ]; then return 1; fi

  # Check TTL
  local now file_age
  now=$(date +%s)
  if stat -f '%m' /dev/null &>/dev/null 2>&1; then
    # macOS
    file_age=$(stat -f '%m' "$cache_file" 2>/dev/null || echo 0)
  else
    # Linux
    file_age=$(stat -c '%Y' "$cache_file" 2>/dev/null || echo 0)
  fi

  local age=$((now - file_age))
  if [ "$age" -gt "$BANG_CACHE_TTL" ]; then
    rm -f "$cache_file"
    return 1
  fi

  cat "$cache_file"
  return 0
}

# Store result in cache
cache_set() {
  if [ "$BANG_CACHE_ENABLED" != "1" ]; then return 0; fi

  local key="$1"
  local value="$2"
  local cache_file="$BANG_CACHE_DIR/$key"

  echo "$value" > "$cache_file"
}

# Invalidate cache for a loader
cache_invalidate() {
  local loader="$1"
  rm -f "$BANG_CACHE_DIR/${loader}_"* 2>/dev/null || true
}

# Clear all cache
cache_clear() {
  rm -rf "${BANG_CACHE_DIR:?}"/* 2>/dev/null || true
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
  echo "bang-framework configuration"
  echo "════════════════════════════════════════"
  echo ""
  echo "Scan/Display:"
  echo "  BANG_SCAN_DEPTH=$BANG_SCAN_DEPTH"
  echo "  BANG_GIT_LOG_COUNT=$BANG_GIT_LOG_COUNT"
  echo "  BANG_DIFF_MAX_LINES=$BANG_DIFF_MAX_LINES"
  echo "  BANG_DOCKER_LOG_LINES=$BANG_DOCKER_LOG_LINES"
  echo "  BANG_HOOK_TIMEOUT=$BANG_HOOK_TIMEOUT"
  echo ""
  echo "Output:"
  echo "  BANG_OUTPUT_FORMAT=$BANG_OUTPUT_FORMAT"
  echo ""
  echo "Cache:"
  echo "  BANG_CACHE_ENABLED=$BANG_CACHE_ENABLED"
  echo "  BANG_CACHE_TTL=${BANG_CACHE_TTL}s"
  echo "  BANG_CACHE_DIR=$BANG_CACHE_DIR"
  echo ""
  echo "Parallel:"
  echo "  BANG_PARALLEL=$BANG_PARALLEL"
  echo "  BANG_PARALLEL_JOBS=$BANG_PARALLEL_JOBS"
  echo ""
  echo "Config files loaded (in order):"
  echo "  1. defaults (built-in)"
  [ -f "$HOME/.claude/bang.conf" ] && echo "  2. $HOME/.claude/bang.conf" || echo "  2. $HOME/.claude/bang.conf (not found)"
  [ -f "$HOME/.claude/bang-framework/.bangrc" ] && echo "  3. $HOME/.claude/bang-framework/.bangrc" || echo "  3. workspace .bangrc (not found)"

  local dir="$PWD"
  local found_project=0
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/.bangrc" ]; then
      echo "  4. $dir/.bangrc"
      found_project=1
      break
    elif [ -f "$dir/.bang/config" ]; then
      echo "  4. $dir/.bang/config"
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
