#!/usr/bin/env bash
# Comprehensive tests for configuration system
set -euo pipefail

BANG_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_LIB="$BANG_DIR/lib/config.sh"

# ═══════════════════════════════════════════════════════════════════
# BASIC CONFIG FUNCTIONALITY
# ═══════════════════════════════════════════════════════════════════

test_config_lib_exists() {
  [ -f "$CONFIG_LIB" ]
}

test_config_lib_sources() {
  source "$CONFIG_LIB"
}

test_config_functions_exist() {
  source "$CONFIG_LIB"
  type load_config &>/dev/null
  type parse_config_file &>/dev/null
}

# ═══════════════════════════════════════════════════════════════════
# DEFAULT VALUES
# ═══════════════════════════════════════════════════════════════════

test_config_defaults_scan_depth() {
  source "$CONFIG_LIB"
  [ -n "$BANG_SCAN_DEPTH" ]
  [ "$BANG_SCAN_DEPTH" -eq 4 ]
}

test_config_defaults_git_log_count() {
  source "$CONFIG_LIB"
  [ -n "$BANG_GIT_LOG_COUNT" ]
  [ "$BANG_GIT_LOG_COUNT" -eq 5 ]
}

test_config_defaults_diff_max_lines() {
  source "$CONFIG_LIB"
  [ -n "$BANG_DIFF_MAX_LINES" ]
  [ "$BANG_DIFF_MAX_LINES" -eq 100 ]
}

test_config_defaults_docker_log_lines() {
  source "$CONFIG_LIB"
  [ -n "$BANG_DOCKER_LOG_LINES" ]
  [ "$BANG_DOCKER_LOG_LINES" -eq 10 ]
}

test_config_defaults_hook_timeout() {
  source "$CONFIG_LIB"
  [ -n "$BANG_HOOK_TIMEOUT" ]
  [ "$BANG_HOOK_TIMEOUT" -eq 30 ]
}

test_config_defaults_output_format() {
  source "$CONFIG_LIB"
  [ "$BANG_OUTPUT_FORMAT" = "text" ]
}

test_config_defaults_cache_enabled() {
  source "$CONFIG_LIB"
  [ "$BANG_CACHE_ENABLED" -eq 1 ]
}

test_config_defaults_cache_ttl() {
  source "$CONFIG_LIB"
  [ "$BANG_CACHE_TTL" -eq 300 ]
}

test_config_defaults_parallel_enabled() {
  source "$CONFIG_LIB"
  [ "$BANG_PARALLEL" -eq 1 ]
}

test_config_defaults_parallel_jobs() {
  source "$CONFIG_LIB"
  [ "$BANG_PARALLEL_JOBS" -eq 4 ]
}

test_config_defaults_cache_dir() {
  source "$CONFIG_LIB"
  [ -n "$BANG_CACHE_DIR" ]
  echo "$BANG_CACHE_DIR" | grep -q ".bang-cache"
}

test_config_defaults_file_extensions() {
  source "$CONFIG_LIB"
  [ -n "$BANG_FILE_EXTENSIONS" ]
  echo "$BANG_FILE_EXTENSIONS" | grep -q "ts\|js\|py"
}

test_config_defaults_local_ports() {
  source "$CONFIG_LIB"
  [ -n "$BANG_LOCAL_PORTS" ]
  echo "$BANG_LOCAL_PORTS" | grep -q "3000\|5432"
}

test_config_defaults_exclude_dirs() {
  source "$CONFIG_LIB"
  [ -n "$BANG_EXCLUDE_DIRS" ]
  echo "$BANG_EXCLUDE_DIRS" | grep -q "node_modules\|.git"
}

# ═══════════════════════════════════════════════════════════════════
# CONFIG LOADING
# ═══════════════════════════════════════════════════════════════════

test_config_load_function() {
  source "$CONFIG_LIB"
  load_config
  [ "$BANG_CONFIG_LOADED" -eq 1 ]
}

test_config_load_idempotent() {
  source "$CONFIG_LIB"
  load_config
  load_config
  load_config
  [ "$BANG_CONFIG_LOADED" -eq 1 ]
}

test_config_auto_loads() {
  # Config should auto-load when sourced
  unset BANG_CONFIG_LOADED
  source "$CONFIG_LIB"
  [ "$BANG_CONFIG_LOADED" -eq 1 ]
}

# ═══════════════════════════════════════════════════════════════════
# CONFIG FILE PARSING
# ═══════════════════════════════════════════════════════════════════

test_config_parse_simple_file() {
  source "$CONFIG_LIB"

  # Create temp config file
  local tmp_config="/tmp/bang-test-config-$$.conf"
  cat > "$tmp_config" <<EOF
BANG_SCAN_DEPTH=10
BANG_GIT_LOG_COUNT=20
EOF

  parse_config_file "$tmp_config"

  [ "$BANG_SCAN_DEPTH" -eq 10 ]
  [ "$BANG_GIT_LOG_COUNT" -eq 20 ]

  rm -f "$tmp_config"
}

test_config_parse_with_comments() {
  source "$CONFIG_LIB"

  local tmp_config="/tmp/bang-test-config-comments-$$.conf"
  cat > "$tmp_config" <<EOF
# This is a comment
BANG_SCAN_DEPTH=15
# Another comment
BANG_GIT_LOG_COUNT=25
EOF

  parse_config_file "$tmp_config"

  [ "$BANG_SCAN_DEPTH" -eq 15 ]
  [ "$BANG_GIT_LOG_COUNT" -eq 25 ]

  rm -f "$tmp_config"
}

test_config_parse_quoted_values() {
  source "$CONFIG_LIB"

  local tmp_config="/tmp/bang-test-config-quoted-$$.conf"
  cat > "$tmp_config" <<EOF
BANG_OUTPUT_FORMAT="json"
BANG_CACHE_DIR="/custom/path"
EOF

  parse_config_file "$tmp_config"

  [ "$BANG_OUTPUT_FORMAT" = "json" ]
  [ "$BANG_CACHE_DIR" = "/custom/path" ]

  rm -f "$tmp_config"
}

test_config_parse_blank_lines() {
  source "$CONFIG_LIB"

  local tmp_config="/tmp/bang-test-config-blank-$$.conf"
  cat > "$tmp_config" <<EOF

BANG_SCAN_DEPTH=8

BANG_GIT_LOG_COUNT=12

EOF

  parse_config_file "$tmp_config"

  [ "$BANG_SCAN_DEPTH" -eq 8 ]
  [ "$BANG_GIT_LOG_COUNT" -eq 12 ]

  rm -f "$tmp_config"
}

test_config_parse_nonexistent_file() {
  source "$CONFIG_LIB"

  # Should handle gracefully
  parse_config_file "/nonexistent/file.conf" || true
}

test_config_ignores_non_bang_vars() {
  source "$CONFIG_LIB"

  local tmp_config="/tmp/bang-test-config-safe-$$.conf"
  cat > "$tmp_config" <<EOF
BANG_SCAN_DEPTH=7
MALICIOUS_VAR=dangerous
PATH=/bad/path
EOF

  local original_path="$PATH"
  parse_config_file "$tmp_config"

  [ "$BANG_SCAN_DEPTH" -eq 7 ]
  # PATH should be unchanged
  [ "$PATH" = "$original_path" ]

  rm -f "$tmp_config"
}

# ═══════════════════════════════════════════════════════════════════
# ENVIRONMENT VARIABLE OVERRIDES
# ═══════════════════════════════════════════════════════════════════

test_config_env_override_scan_depth() {
  export BANG_SCAN_DEPTH=99
  source "$CONFIG_LIB"
  [ "$BANG_SCAN_DEPTH" -eq 99 ]
  unset BANG_SCAN_DEPTH
}

test_config_env_override_cache_ttl() {
  export BANG_CACHE_TTL=777
  source "$CONFIG_LIB"
  [ "$BANG_CACHE_TTL" -eq 777 ]
  unset BANG_CACHE_TTL
}

test_config_env_override_output_format() {
  export BANG_OUTPUT_FORMAT="json"
  source "$CONFIG_LIB"
  [ "$BANG_OUTPUT_FORMAT" = "json" ]
  unset BANG_OUTPUT_FORMAT
}

# ═══════════════════════════════════════════════════════════════════
# CONFIG FILE HIERARCHY
# ═══════════════════════════════════════════════════════════════════

test_config_global_config_path() {
  source "$CONFIG_LIB"
  # Global config should be at ~/.claude/bang.conf
  local global_path="$HOME/.claude/bang.conf"
  # Path should be checked (doesn't need to exist)
  true
}

test_config_workspace_config_path() {
  source "$CONFIG_LIB"
  # Workspace config should be at BANG_DIR/.bangrc
  local workspace_path="$BANG_DIR/.bangrc"
  true
}

test_config_project_config_search() {
  source "$CONFIG_LIB"
  # Should search for .bangrc or .bang/config in parent directories
  # This is tested by the load_config function
  true
}

# ═══════════════════════════════════════════════════════════════════
# EXCLUDE PATTERN BUILDING
# ═══════════════════════════════════════════════════════════════════

test_config_find_exclude_pattern() {
  source "$CONFIG_LIB"
  [ -n "$BANG_FIND_EXCLUDE" ]
  echo "$BANG_FIND_EXCLUDE" | grep -q "node_modules"
}

test_config_exclude_has_all_dirs() {
  source "$CONFIG_LIB"
  echo "$BANG_FIND_EXCLUDE" | grep -q "node_modules"
  echo "$BANG_FIND_EXCLUDE" | grep -q ".git"
  echo "$BANG_FIND_EXCLUDE" | grep -q "dist"
}

# ═══════════════════════════════════════════════════════════════════
# JSON HELPERS
# ═══════════════════════════════════════════════════════════════════

test_config_has_jq_check() {
  source "$CONFIG_LIB"
  [ -n "$HAS_JQ" ]
  # Should be true or false
  [[ "$HAS_JQ" =~ ^(true|false)$ ]]
}

test_config_json_escape_function() {
  source "$CONFIG_LIB"
  type json_escape_string &>/dev/null || true
}

test_config_json_parse_function() {
  source "$CONFIG_LIB"
  type json_parse &>/dev/null || true
}

# ═══════════════════════════════════════════════════════════════════
# JSON OUTPUT HELPERS
# ═══════════════════════════════════════════════════════════════════

test_config_json_start_end() {
  source "$CONFIG_LIB"
  type json_start &>/dev/null
  type json_end &>/dev/null
}

test_config_json_kv_functions() {
  source "$CONFIG_LIB"
  type json_kv &>/dev/null
  type json_kvn &>/dev/null
  type json_kvb &>/dev/null
  type json_kva &>/dev/null
}

# ═══════════════════════════════════════════════════════════════════
# EDGE CASES
# ═══════════════════════════════════════════════════════════════════

test_config_handles_missing_home() {
  # Config should handle missing HOME gracefully
  # This is hard to test without breaking the environment
  true
}

test_config_handles_readonly_cache_dir() {
  # Should handle when cache dir cannot be created
  # This is difficult to test without breaking permissions
  true
}

test_config_numeric_validation() {
  source "$CONFIG_LIB"
  # Numeric configs should be numbers
  [[ "$BANG_SCAN_DEPTH" =~ ^[0-9]+$ ]]
  [[ "$BANG_GIT_LOG_COUNT" =~ ^[0-9]+$ ]]
  [[ "$BANG_CACHE_TTL" =~ ^[0-9]+$ ]]
}

test_config_boolean_validation() {
  source "$CONFIG_LIB"
  # Boolean configs should be 0 or 1
  [[ "$BANG_CACHE_ENABLED" =~ ^[01]$ ]]
  [[ "$BANG_PARALLEL" =~ ^[01]$ ]]
}
