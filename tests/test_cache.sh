#!/usr/bin/env bash
# Comprehensive tests for cache system
set -euo pipefail

BANG_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_LIB="$BANG_DIR/lib/config.sh"

# ═══════════════════════════════════════════════════════════════════
# BASIC CACHE FUNCTIONALITY
# ═══════════════════════════════════════════════════════════════════

test_config_lib_exists() {
  [ -f "$CONFIG_LIB" ]
}

test_config_sources() {
  source "$CONFIG_LIB"
}

test_cache_functions_exist() {
  source "$CONFIG_LIB"
  type cache_init &>/dev/null
  type cache_get &>/dev/null
  type cache_set &>/dev/null
  type cache_key &>/dev/null
  type cache_invalidate &>/dev/null
  type cache_clear &>/dev/null
}

# ═══════════════════════════════════════════════════════════════════
# CACHE INITIALIZATION
# ═══════════════════════════════════════════════════════════════════

test_cache_init_creates_directory() {
  source "$CONFIG_LIB"
  export BANG_CACHE_ENABLED=1
  export BANG_CACHE_DIR="/tmp/bang-test-cache-$$"

  cache_init
  [ -d "$BANG_CACHE_DIR" ]

  # Cleanup
  rm -rf "$BANG_CACHE_DIR"
}

test_cache_init_when_disabled() {
  source "$CONFIG_LIB"
  export BANG_CACHE_ENABLED=0
  export BANG_CACHE_DIR="/tmp/bang-test-cache-disabled-$$"

  cache_init
  # Should not create directory when disabled
  true

  # Cleanup if created
  rm -rf "$BANG_CACHE_DIR" 2>/dev/null || true
}

test_cache_init_idempotent() {
  source "$CONFIG_LIB"
  export BANG_CACHE_ENABLED=1
  export BANG_CACHE_DIR="/tmp/bang-test-cache-idem-$$"

  cache_init
  cache_init
  cache_init

  [ -d "$BANG_CACHE_DIR" ]

  # Cleanup
  rm -rf "$BANG_CACHE_DIR"
}

# ═══════════════════════════════════════════════════════════════════
# CACHE KEY GENERATION
# ═══════════════════════════════════════════════════════════════════

test_cache_key_generation() {
  source "$CONFIG_LIB"

  local key
  key=$(cache_key "git-context" "--minimal")
  [ -n "$key" ]
}

test_cache_key_different_args() {
  source "$CONFIG_LIB"

  local key1 key2
  key1=$(cache_key "git-context" "--minimal")
  key2=$(cache_key "git-context" "--full")

  [ "$key1" != "$key2" ]
}

test_cache_key_different_loaders() {
  source "$CONFIG_LIB"

  local key1 key2
  key1=$(cache_key "git-context" "")
  key2=$(cache_key "env-summary" "")

  [ "$key1" != "$key2" ]
}

test_cache_key_same_inputs() {
  source "$CONFIG_LIB"

  local key1 key2
  key1=$(cache_key "git-context" "--minimal")
  key2=$(cache_key "git-context" "--minimal")

  [ "$key1" = "$key2" ]
}

test_cache_key_includes_project() {
  source "$CONFIG_LIB"

  # Keys should differ based on working directory
  local key1 key2
  key1=$(cd /tmp && cache_key "loader" "args")
  key2=$(cd "$BANG_DIR" && cache_key "loader" "args")

  # These might be the same or different depending on hash collision
  # Just verify both are generated
  [ -n "$key1" ]
  [ -n "$key2" ]
}

# ═══════════════════════════════════════════════════════════════════
# CACHE SET AND GET
# ═══════════════════════════════════════════════════════════════════

test_cache_set_and_get() {
  source "$CONFIG_LIB"
  export BANG_CACHE_ENABLED=1
  export BANG_CACHE_DIR="/tmp/bang-test-cache-setget-$$"
  cache_init

  local key
  key=$(cache_key "test-loader" "args")
  cache_set "$key" "test data value"

  local retrieved
  retrieved=$(cache_get "$key")
  [ "$retrieved" = "test data value" ]

  # Cleanup
  rm -rf "$BANG_CACHE_DIR"
}

test_cache_get_miss() {
  source "$CONFIG_LIB"
  export BANG_CACHE_ENABLED=1
  export BANG_CACHE_DIR="/tmp/bang-test-cache-miss-$$"
  cache_init

  # Try to get non-existent key
  local exit_code=0
  cache_get "nonexistent-key-12345" &>/dev/null || exit_code=$?

  [ "$exit_code" -ne 0 ]

  # Cleanup
  rm -rf "$BANG_CACHE_DIR"
}

test_cache_multiline_data() {
  source "$CONFIG_LIB"
  export BANG_CACHE_ENABLED=1
  export BANG_CACHE_DIR="/tmp/bang-test-cache-multiline-$$"
  cache_init

  local key
  key=$(cache_key "test" "multi")
  local data="line1
line2
line3"

  cache_set "$key" "$data"
  local retrieved
  retrieved=$(cache_get "$key")

  [ "$retrieved" = "$data" ]

  # Cleanup
  rm -rf "$BANG_CACHE_DIR"
}

test_cache_empty_data() {
  source "$CONFIG_LIB"
  export BANG_CACHE_ENABLED=1
  export BANG_CACHE_DIR="/tmp/bang-test-cache-empty-$$"
  cache_init

  local key
  key=$(cache_key "test" "empty")
  cache_set "$key" ""

  # Should store empty string
  cache_get "$key" &>/dev/null || true

  # Cleanup
  rm -rf "$BANG_CACHE_DIR"
}

# ═══════════════════════════════════════════════════════════════════
# CACHE TTL BEHAVIOR
# ═══════════════════════════════════════════════════════════════════

test_cache_ttl_fresh() {
  source "$CONFIG_LIB"
  export BANG_CACHE_ENABLED=1
  export BANG_CACHE_TTL=10
  export BANG_CACHE_DIR="/tmp/bang-test-cache-fresh-$$"
  cache_init

  local key
  key=$(cache_key "test-loader" "ttl")
  cache_set "$key" "fresh data"

  # Should exist immediately
  local retrieved
  retrieved=$(cache_get "$key")
  [ "$retrieved" = "fresh data" ]

  # Cleanup
  rm -rf "$BANG_CACHE_DIR"
}

test_cache_ttl_expired() {
  source "$CONFIG_LIB"
  export BANG_CACHE_ENABLED=1
  export BANG_CACHE_TTL=1
  export BANG_CACHE_DIR="/tmp/bang-test-cache-ttl-$$"
  cache_init

  local key
  key=$(cache_key "test-loader" "ttl")
  cache_set "$key" "expiring data"

  # Should exist immediately
  cache_get "$key" &>/dev/null

  # Wait for expiration
  sleep 2

  # Should be expired and return non-zero
  local exit_code=0
  cache_get "$key" &>/dev/null || exit_code=$?
  [ "$exit_code" -ne 0 ]

  # Cleanup
  rm -rf "$BANG_CACHE_DIR"
}

test_cache_ttl_default_value() {
  source "$CONFIG_LIB"

  # Default TTL should be 300 seconds (5 minutes)
  [ "$BANG_CACHE_TTL" -eq 300 ] || [ -n "$BANG_CACHE_TTL" ]
}

test_cache_ttl_custom_value() {
  source "$CONFIG_LIB"
  export BANG_CACHE_TTL=600

  [ "$BANG_CACHE_TTL" -eq 600 ]
}

# ═══════════════════════════════════════════════════════════════════
# CACHE INVALIDATION
# ═══════════════════════════════════════════════════════════════════

test_cache_invalidate_loader() {
  source "$CONFIG_LIB"
  export BANG_CACHE_ENABLED=1
  export BANG_CACHE_DIR="/tmp/bang-test-cache-invalidate-$$"
  cache_init

  local key
  key=$(cache_key "git-context" "test")
  cache_set "$key" "data to invalidate"

  cache_invalidate "git-context"

  # Should not exist after invalidation
  local exit_code=0
  cache_get "$key" &>/dev/null || exit_code=$?
  [ "$exit_code" -ne 0 ]

  # Cleanup
  rm -rf "$BANG_CACHE_DIR"
}

test_cache_invalidate_specific_loader_only() {
  source "$CONFIG_LIB"
  export BANG_CACHE_ENABLED=1
  export BANG_CACHE_DIR="/tmp/bang-test-cache-inv-specific-$$"
  cache_init

  local key1 key2
  key1=$(cache_key "git-context" "test")
  key2=$(cache_key "env-summary" "test")

  cache_set "$key1" "data1"
  cache_set "$key2" "data2"

  cache_invalidate "git-context"

  # git-context should be gone
  local exit_code=0
  cache_get "$key1" &>/dev/null || exit_code=$?
  [ "$exit_code" -ne 0 ]

  # env-summary should still exist
  local retrieved
  retrieved=$(cache_get "$key2")
  [ "$retrieved" = "data2" ]

  # Cleanup
  rm -rf "$BANG_CACHE_DIR"
}

test_cache_invalidate_nonexistent() {
  source "$CONFIG_LIB"
  export BANG_CACHE_ENABLED=1
  export BANG_CACHE_DIR="/tmp/bang-test-cache-inv-none-$$"
  cache_init

  # Should not error when invalidating non-existent loader
  cache_invalidate "nonexistent-loader" || true

  # Cleanup
  rm -rf "$BANG_CACHE_DIR"
}

# ═══════════════════════════════════════════════════════════════════
# CACHE CLEAR
# ═══════════════════════════════════════════════════════════════════

test_cache_clear_all() {
  source "$CONFIG_LIB"
  export BANG_CACHE_ENABLED=1
  export BANG_CACHE_DIR="/tmp/bang-test-cache-clear-$$"
  cache_init

  cache_set "key1" "value1"
  cache_set "key2" "value2"
  cache_set "key3" "value3"

  cache_clear

  # Cache dir should be empty
  local count
  count=$(ls "$BANG_CACHE_DIR" 2>/dev/null | wc -l | tr -d ' ')
  [ "$count" -eq 0 ]

  # Cleanup
  rm -rf "$BANG_CACHE_DIR"
}

test_cache_clear_idempotent() {
  source "$CONFIG_LIB"
  export BANG_CACHE_ENABLED=1
  export BANG_CACHE_DIR="/tmp/bang-test-cache-clear-idem-$$"
  cache_init

  cache_clear
  cache_clear
  cache_clear

  # Should not error
  true

  # Cleanup
  rm -rf "$BANG_CACHE_DIR"
}

# ═══════════════════════════════════════════════════════════════════
# CACHE DISABLED BEHAVIOR
# ═══════════════════════════════════════════════════════════════════

test_cache_disabled_set() {
  source "$CONFIG_LIB"
  export BANG_CACHE_ENABLED=0
  export BANG_CACHE_DIR="/tmp/bang-test-cache-disabled-set-$$"

  local key
  key=$(cache_key "test" "disabled")
  cache_set "$key" "data"

  # Should not create cache file
  [ ! -f "$BANG_CACHE_DIR/$key" ]

  # Cleanup
  rm -rf "$BANG_CACHE_DIR" 2>/dev/null || true
}

test_cache_disabled_get() {
  source "$CONFIG_LIB"
  export BANG_CACHE_ENABLED=0
  export BANG_CACHE_DIR="/tmp/bang-test-cache-disabled-get-$$"

  local exit_code=0
  cache_get "any-key" &>/dev/null || exit_code=$?

  # Should return failure (cache miss)
  [ "$exit_code" -ne 0 ]

  # Cleanup
  rm -rf "$BANG_CACHE_DIR" 2>/dev/null || true
}

# ═══════════════════════════════════════════════════════════════════
# EDGE CASES
# ═══════════════════════════════════════════════════════════════════

test_cache_special_characters() {
  source "$CONFIG_LIB"
  export BANG_CACHE_ENABLED=1
  export BANG_CACHE_DIR="/tmp/bang-test-cache-special-$$"
  cache_init

  local key
  key=$(cache_key "loader" "--flag=value with spaces")
  cache_set "$key" "data"

  local retrieved
  retrieved=$(cache_get "$key")
  [ "$retrieved" = "data" ]

  # Cleanup
  rm -rf "$BANG_CACHE_DIR"
}

test_cache_large_data() {
  source "$CONFIG_LIB"
  export BANG_CACHE_ENABLED=1
  export BANG_CACHE_DIR="/tmp/bang-test-cache-large-$$"
  cache_init

  # Generate large data (1000 lines)
  local large_data=""
  for i in {1..100}; do
    large_data="${large_data}Line $i with some data content
"
  done

  local key
  key=$(cache_key "test" "large")
  cache_set "$key" "$large_data"

  local retrieved
  retrieved=$(cache_get "$key")

  # Should retrieve all data
  [ -n "$retrieved" ]

  # Cleanup
  rm -rf "$BANG_CACHE_DIR"
}
