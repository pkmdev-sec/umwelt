#!/usr/bin/env bash
# Tests for edge cases and error handling
set -euo pipefail

UMWELT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
UMWELT_BIN="$UMWELT_DIR/bang"

# Test: nonexistent loader
test_nonexistent_loader() {
  ! "$UMWELT_BIN" nonexistent-loader &>/dev/null
}

# Test: nonexistent profile
test_nonexistent_profile() {
  ! "$UMWELT_BIN" profile nonexistent &>/dev/null
}

# Test: umwelt with no arguments shows help
test_no_arguments() {
  "$UMWELT_BIN" &>/dev/null
}

# Test: umwelt --help works
test_help_flag() {
  "$UMWELT_BIN" --help &>/dev/null
}

# Test: umwelt --version works
test_version_flag() {
  "$UMWELT_BIN" --version | grep -q "bang v"
}

# Test: umwelt list works
test_list_command() {
  "$UMWELT_BIN" list | grep -q "Available Loaders"
}

# Test: loader with missing dependencies (docker not running)
test_loader_missing_dependency() {
  # docker-status should handle missing docker gracefully
  "$UMWELT_DIR/loaders/docker-status.sh" &>/dev/null
}

# Test: git-context outside git repo
test_git_context_no_repo() {
  (
    cd /tmp
    "$UMWELT_DIR/loaders/git-context.sh" 2>/dev/null | grep -q "Not a git repository"
  )
}

# Test: JSON mode with invalid output
test_json_mode_fallback() {
  # Even if JSON generation fails, should not crash
  "$UMWELT_DIR/loaders/env-summary.sh" --json &>/dev/null
}

# Test: parallel execution with no loaders
test_parallel_empty() {
  source "$UMWELT_DIR/lib/parallel.sh"
  export UMWELT_DIR
  parallel_run &>/dev/null || true
}

# Test: config parsing with missing config files
test_missing_config_files() {
  source "$UMWELT_DIR/lib/config.sh"
  # Should load defaults even without config files
  [ -n "$UMWELT_SCAN_DEPTH" ]
}

# Test: output.sh library functions
test_output_lib_exists() {
  [ -f "$UMWELT_DIR/lib/output.sh" ]
}

test_output_lib_sources() {
  source "$UMWELT_DIR/lib/output.sh"
  type text_header &>/dev/null
  type json_escape &>/dev/null
}

# Test: jq availability detection
test_jq_detection() {
  source "$UMWELT_DIR/lib/output.sh"
  # Should set HAS_JQ variable
  [[ "$HAS_JQ" == "true" || "$HAS_JQ" == "false" ]]
}

# Test: JSON functions work without jq
test_json_without_jq() {
  (
    # Temporarily hide jq
    export PATH="/usr/bin:/bin"
    source "$UMWELT_DIR/lib/output.sh"

    # json_escape should still work via python3 fallback
    local result
    result=$(json_escape "test string" 2>/dev/null || echo "")
    [ -n "$result" ]
  )
}
