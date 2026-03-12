#!/usr/bin/env bash
# bang-framework: Event-Optimized Loading (Innovation 4)
# Routes hook events to optimal loader subsets instead of running everything.
# Different events trigger different loading strategies based on what data
# is likely stale or needed.
#
# Event → Loader mapping:
#   SessionStart      → ALL loaders (full environment scan)
#   UserPromptSubmit  → git-context (if .git/index changed), docker-status (if >5min), processes (if >2min)
#   PreCompact        → env-summary (stable, for preservation), git-context
#   PostToolUse(Bash) → git-context (always), docker-status (if cmd had docker), test-status (if cmd had test/npm)
#
# Usage: source this file, then call route_event / should_rescan / get_trigger_loaders

BANG_DIR="${BANG_DIR:-$HOME/.claude/bang-framework}"
CACHE_DIR="${BANG_CACHE_DIR:-$HOME/.claude/.bang-cache}"

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
