#!/usr/bin/env bash
# ============================================================================
# event-router.sh — Event-optimized loading (Innovation 4)
# ============================================================================
# Purpose: Routes Claude Code hook events to optimal loader subsets. Full
#          scan on SessionStart, lightweight context-aware updates on other
#          events. Includes custom event mapping configuration support.
#
# Usage: source lib/event-router.sh
#        Call: route_event "SessionStart|UserPromptSubmit|PreCompact|PostToolUse" ["bash_cmd"]
#              route_event_with_custom (includes custom mappings)
#              add_custom_event_mapping, list_custom_event_mappings
#
# Dependencies: bash 3.2+, git (for index mtime detection)
#
# Output: Space-separated list of loader names to run for the given event.
#         Event mappings: SessionStart→all, UserPromptSubmit→git+docker+test,
#         PreCompact→env+git, PostToolUse→git+conditional based on command.
#         Custom mappings: ~/.claude/umwelt/event-mappings.conf
# ============================================================================

UMWELT_DIR="${UMWELT_DIR:-$HOME/.claude/umwelt}"
CACHE_DIR="${UMWELT_CACHE_DIR:-$HOME/.claude/.bang-cache}"

# Ensure cache dir exists
mkdir -p "$CACHE_DIR"

# All known loaders
ALL_LOADERS="env-summary git-context docker-status api-health test-status deps-audit project-summary"

# ─── Timestamp helpers ──────────────────────────────────────────
_now_epoch() {
  date +%s
}

_file_mtime() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "0"
    return
  fi
  if stat -f '%m' /dev/null &>/dev/null 2>&1; then
    stat -f '%m' "$file" 2>/dev/null || echo "0"
  else
    stat -c '%Y' "$file" 2>/dev/null || echo "0"
  fi
}

_seconds_since_last_run() {
  local loader="$1"
  local ts_file="$CACHE_DIR/event-router-${loader}-ts"
  if [ ! -f "$ts_file" ]; then
    echo "999999"
    return
  fi
  local last_ts
  last_ts=$(cat "$ts_file" 2>/dev/null || echo "0")
  local now
  now=$(_now_epoch)
  echo $(( now - last_ts ))
}

_record_loader_run() {
  local loader="$1"
  local ts_file="$CACHE_DIR/event-router-${loader}-ts"
  _now_epoch > "$ts_file"
}

# ─── Git index change detection ─────────────────────────────────
_git_index_changed() {
  # Check if .git/index mtime is newer than our last recorded run
  local git_dir
  git_dir=$(git rev-parse --git-dir 2>/dev/null) || return 1
  local index_file="$git_dir/index"
  [ ! -f "$index_file" ] && return 1

  local index_mtime
  index_mtime=$(_file_mtime "$index_file")
  local last_run_file="$CACHE_DIR/event-router-git-context-ts"
  if [ ! -f "$last_run_file" ]; then
    return 0  # Never run, so yes it "changed"
  fi
  local last_ts
  last_ts=$(cat "$last_run_file" 2>/dev/null || echo "0")
  [ "$index_mtime" -gt "$last_ts" ] 2>/dev/null
}

# ─── should_rescan ──────────────────────────────────────────────
# Decides if a specific loader needs re-running for a given event.
# Args: loader_name event_type [bash_command]
# Returns: 0 (yes, rescan) or 1 (no, skip)
should_rescan() {
  local loader="$1"
  local event="$2"
  local bash_cmd="${3:-}"

  case "$event" in
    SessionStart)
      # Always rescan everything on session start
      return 0
      ;;
    UserPromptSubmit)
      case "$loader" in
        git-context)
          _git_index_changed && return 0
          return 1
          ;;
        docker-status)
          local elapsed
          elapsed=$(_seconds_since_last_run "docker-status")
          [ "$elapsed" -gt 300 ] && return 0  # >5 min
          return 1
          ;;
        test-status)
          local elapsed
          elapsed=$(_seconds_since_last_run "test-status")
          [ "$elapsed" -gt 120 ] && return 0  # >2 min
          return 1
          ;;
        *)
          return 1
          ;;
      esac
      ;;
    PreCompact)
      case "$loader" in
        env-summary|git-context)
          return 0  # Always inject these for compaction survival
          ;;
        *)
          return 1
          ;;
      esac
      ;;
    PostToolUse)
      case "$loader" in
        git-context)
          return 0  # Always rescan git after bash
          ;;
        docker-status)
          echo "$bash_cmd" | grep -qiE '(docker|compose|container)' && return 0
          return 1
          ;;
        test-status)
          echo "$bash_cmd" | grep -qiE '(test|jest|pytest|mocha|vitest|npm run|yarn test|cargo test|go test)' && return 0
          return 1
          ;;
        *)
          return 1
          ;;
      esac
      ;;
    *)
      return 1
      ;;
  esac
}

# ─── get_trigger_loaders ────────────────────────────────────────
# Maps an event type to its minimal set of candidate loaders.
# Args: event_type [bash_command]
# Output: space-separated list of loader names to stdout
get_trigger_loaders() {
  local event="$1"
  local bash_cmd="${2:-}"

  case "$event" in
    SessionStart)
      echo "$ALL_LOADERS"
      ;;
    UserPromptSubmit)
      echo "git-context docker-status test-status"
      ;;
    PreCompact)
      echo "env-summary git-context"
      ;;
    PostToolUse)
      local loaders="git-context"
      if echo "$bash_cmd" | grep -qiE '(docker|compose|container)'; then
        loaders="$loaders docker-status"
      fi
      if echo "$bash_cmd" | grep -qiE '(test|jest|pytest|mocha|vitest|npm run|yarn test|cargo test|go test)'; then
        loaders="$loaders test-status"
      fi
      echo "$loaders"
      ;;
    *)
      echo ""
      ;;
  esac
}

# ─── route_event ────────────────────────────────────────────────
# Main entry point: given an event, returns the list of loaders that
# actually need to run (applying should_rescan filtering).
# Args: event_type [bash_command]
# Output: space-separated list of loaders to run
route_event() {
  local event="$1"
  local bash_cmd="${2:-}"

  local candidates
  candidates=$(get_trigger_loaders "$event" "$bash_cmd")

  local result=""
  for loader in $candidates; do
    if should_rescan "$loader" "$event" "$bash_cmd"; then
      result="$result $loader"
    fi
  done

  # Trim leading space
  echo "$result" | sed 's/^ //'
}

# ─── record_run ─────────────────────────────────────────────────
# Call after running loaders to record timestamps for staleness checks.
# Args: loader_name [loader_name ...]
record_loader_runs() {
  for loader in "$@"; do
    _record_loader_run "$loader"
  done
}

# ─── Custom Event Mapping (P1 Feature) ──────────────────────────

UMWELT_EVENT_CONFIG="${UMWELT_EVENT_CONFIG:-$HOME/.claude/umwelt/event-mappings.conf}"

# Load custom event mappings from config file
# Format: EVENT_NAME:loader1,loader2,loader3
# Example:
#   CustomBuild:project-summary,deps-audit
#   OnCommit:git-context,test-status
load_custom_event_mappings() {
  if [ ! -f "$UMWELT_EVENT_CONFIG" ]; then
    return 0
  fi

  # Parse config file
  while IFS= read -r line || [ -n "$line" ]; do
    # Skip comments and blank lines
    line=$(echo "$line" | sed 's/#.*//' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    if [ -z "$line" ]; then continue; fi

    # Parse EVENT:loaders format
    local event_name
    event_name=$(echo "$line" | cut -d':' -f1 | tr -d ' ')
    local loaders
    loaders=$(echo "$line" | cut -d':' -f2- | tr ',' ' ')

    if [ -n "$event_name" ] && [ -n "$loaders" ]; then
      # Store in cache for fast lookup
      echo "$loaders" > "$CACHE_DIR/event-custom-${event_name}" 2>/dev/null || true
    fi
  done < "$UMWELT_EVENT_CONFIG"
}

# Get custom event mapping if defined
# Args: event_name
# Output: space-separated loader list or empty if not defined
get_custom_event_mapping() {
  local event="$1"
  local mapping_file="$CACHE_DIR/event-custom-${event}"

  if [ -f "$mapping_file" ]; then
    cat "$mapping_file" 2>/dev/null || echo ""
  else
    echo ""
  fi
}

# Check if a custom event mapping exists
# Args: event_name
# Returns: 0 if exists, 1 if not
has_custom_event_mapping() {
  local event="$1"
  local mapping_file="$CACHE_DIR/event-custom-${event}"
  [ -f "$mapping_file" ]
}

# Enhanced get_trigger_loaders with custom mapping support
# Args: event_type [bash_command]
# Output: space-separated list of loader names to stdout
get_trigger_loaders_with_custom() {
  local event="$1"
  local bash_cmd="${2:-}"

  # Check for custom mapping first
  local custom_loaders
  custom_loaders=$(get_custom_event_mapping "$event")

  if [ -n "$custom_loaders" ]; then
    echo "$custom_loaders"
    return
  fi

  # Fall back to default mappings
  get_trigger_loaders "$event" "$bash_cmd"
}

# Enhanced route_event with custom mapping support
# Args: event_type [bash_command]
# Output: space-separated list of loaders to run
route_event_with_custom() {
  local event="$1"
  local bash_cmd="${2:-}"

  local candidates
  candidates=$(get_trigger_loaders_with_custom "$event" "$bash_cmd")

  local result=""
  for loader in $candidates; do
    if should_rescan "$loader" "$event" "$bash_cmd"; then
      result="$result $loader"
    fi
  done

  # Trim leading space
  echo "$result" | sed 's/^ //'
}

# Add a custom event mapping
# Usage: add_custom_event_mapping "EventName" "loader1 loader2 loader3"
add_custom_event_mapping() {
  local event_name="${1:-}"
  local loaders="${2:-}"

  if [ -z "$event_name" ]; then
    echo "Error: Event name required" >&2
    return 1
  fi

  if [ -z "$loaders" ]; then
    echo "Error: Loader list required" >&2
    return 1
  fi

  # Validate loaders
  for loader in $loaders; do
    case "$loader" in
      env-summary|git-context|docker-status|api-health|test-status|deps-audit|project-summary)
        ;;
      *)
        echo "Warning: Unknown loader '$loader'" >&2
        ;;
    esac
  done

  # Create config file if it doesn't exist
  local config_dir
  config_dir=$(dirname "$UMWELT_EVENT_CONFIG")
  if [ ! -d "$config_dir" ]; then
    mkdir -p "$config_dir" 2>/dev/null || {
      echo "Error: Failed to create config directory" >&2
      return 1
    }
  fi

  # Check if event already exists in config
  if [ -f "$UMWELT_EVENT_CONFIG" ]; then
    if grep -q "^${event_name}:" "$UMWELT_EVENT_CONFIG" 2>/dev/null; then
      # Update existing entry
      local tmpfile
      tmpfile=$(mktemp)
      grep -v "^${event_name}:" "$UMWELT_EVENT_CONFIG" > "$tmpfile" 2>/dev/null || true
      echo "${event_name}:${loaders// /,}" >> "$tmpfile"
      mv "$tmpfile" "$UMWELT_EVENT_CONFIG"
    else
      # Append new entry
      echo "${event_name}:${loaders// /,}" >> "$UMWELT_EVENT_CONFIG"
    fi
  else
    # Create new config file
    echo "${event_name}:${loaders// /,}" > "$UMWELT_EVENT_CONFIG"
  fi

  # Reload mappings
  load_custom_event_mappings
  echo "Custom event mapping added: $event_name -> $loaders"
}

# Remove a custom event mapping
# Usage: remove_custom_event_mapping "EventName"
remove_custom_event_mapping() {
  local event_name="${1:-}"

  if [ -z "$event_name" ]; then
    echo "Error: Event name required" >&2
    return 1
  fi

  if [ -f "$UMWELT_EVENT_CONFIG" ]; then
    local tmpfile
    tmpfile=$(mktemp)
    grep -v "^${event_name}:" "$UMWELT_EVENT_CONFIG" > "$tmpfile" 2>/dev/null || true
    mv "$tmpfile" "$UMWELT_EVENT_CONFIG"
  fi

  # Remove cache
  rm -f "$CACHE_DIR/event-custom-${event_name}" 2>/dev/null || true
  echo "Custom event mapping removed: $event_name"
}

# List all custom event mappings
# Usage: list_custom_event_mappings
list_custom_event_mappings() {
  if [ ! -f "$UMWELT_EVENT_CONFIG" ]; then
    echo "No custom event mappings configured"
    return
  fi

  echo "Custom Event Mappings"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  while IFS= read -r line || [ -n "$line" ]; do
    line=$(echo "$line" | sed 's/#.*//' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    if [ -z "$line" ]; then continue; fi

    local event_name
    event_name=$(echo "$line" | cut -d':' -f1)
    local loaders
    loaders=$(echo "$line" | cut -d':' -f2- | tr ',' ' ')

    printf "%-20s → %s\n" "$event_name" "$loaders"
  done < "$UMWELT_EVENT_CONFIG"
}

# Load custom mappings on source
load_custom_event_mappings
