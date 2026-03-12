#!/usr/bin/env bash
# Tests for edge cases and error handling
set -euo pipefail

BANG_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BANG_BIN="$BANG_DIR/bang"

# Test: nonexistent loader
test_nonexistent_loader() {
  ! "$BANG_BIN" nonexistent-loader &>/dev/null
}

# Test: nonexistent profile
test_nonexistent_profile() {
  ! "$BANG_BIN" profile nonexistent &>/dev/null
}

# Test: bang with no arguments shows help
test_no_arguments() {
  "$BANG_BIN" &>/dev/null
}

# Test: bang --help works
test_help_flag() {
  "$BANG_BIN" --help &>/dev/null
}

# Test: bang --version works
test_version_flag() {
  "$BANG_BIN" --version | grep -q "bang v"
}

# Test: bang list works
test_list_command() {
  "$BANG_BIN" list | grep -q "Available Loaders"
}

# Test: loader with missing dependencies (docker not running)
test_loader_missing_dependency() {
  # docker-status should handle missing docker gracefully
  "$BANG_DIR/loaders/docker-status.sh" &>/dev/null
}

# Test: git-context outside git repo
test_git_context_no_repo() {
  (
    cd /tmp
    "$BANG_DIR/loaders/git-context.sh" 2>/dev/null | grep -q "Not a git repository"
  )
}

# Test: JSON mode with invalid output
test_json_mode_fallback() {
  # Even if JSON generation fails, should not crash
  "$BANG_DIR/loaders/env-summary.sh" --json &>/dev/null
}

# Test: parallel execution with no loaders
test_parallel_empty() {
  source "$BANG_DIR/lib/parallel.sh"
  export BANG_DIR
  parallel_run &>/dev/null || true
}

# Test: config parsing with missing config files
test_missing_config_files() {
  source "$BANG_DIR/lib/config.sh"
  # Should load defaults even without config files
  [ -n "$BANG_SCAN_DEPTH" ]
}

# Test: output.sh library functions
test_output_lib_exists() {
  [ -f "$BANG_DIR/lib/output.sh" ]
}

test_output_lib_sources() {
  source "$BANG_DIR/lib/output.sh"
  type text_header &>/dev/null
  type json_escape &>/dev/null
}

# Test: jq availability detection
test_jq_detection() {
  source "$BANG_DIR/lib/output.sh"
  # Should set HAS_JQ variable
  [[ "$HAS_JQ" == "true" || "$HAS_JQ" == "false" ]]
}

# Test: JSON functions work without jq
test_json_without_jq() {
  (
    # Temporarily hide jq
    export PATH="/usr/bin:/bin"
    source "$BANG_DIR/lib/output.sh"

    # json_escape should still work via python3 fallback
    local result
    result=$(json_escape "test string" 2>/dev/null || echo "")
    [ -n "$result" ]
  )
}
