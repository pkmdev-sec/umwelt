#!/usr/bin/env bash
# Tests for caching system
set -euo pipefail

UMWELT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_LIB="$UMWELT_DIR/lib/config.sh"

# Test: config.sh can be sourced
test_config_sources() {
  source "$CONFIG_LIB"
}

# Test: cache initialization
test_cache_init() {
  source "$CONFIG_LIB"
  export UMWELT_CACHE_ENABLED=1
  cache_init
  [ -d "$UMWELT_CACHE_DIR" ]
}

# Test: cache key generation
test_cache_key_generation() {
  source "$CONFIG_LIB"

  local key1
  key1=$(cache_key "git-context" "--minimal")
  [ -n "$key1" ]

  local key2
  key2=$(cache_key "git-context" "--full")
  [ "$key1" != "$key2" ]
}

# Test: cache set and get
test_cache_set_and_get() {
  source "$CONFIG_LIB"
  export UMWELT_CACHE_ENABLED=1
  cache_init

  local key
  key=$(cache_key "test-loader" "args")
  cache_set "$key" "test data"

  local retrieved
  retrieved=$(cache_get "$key")
  [ "$retrieved" = "test data" ]
}

# Test: cache TTL expiration
test_cache_ttl() {
  source "$CONFIG_LIB"
  export UMWELT_CACHE_ENABLED=1
  export UMWELT_CACHE_TTL=1
  cache_init

  local key
  key=$(cache_key "test-loader" "ttl")
  cache_set "$key" "expiring data"

  # Should exist immediately
  cache_get "$key" &>/dev/null

  # Wait for expiration
  sleep 2

  # Should be expired (this will return 1)
  ! cache_get "$key" &>/dev/null
}

# Test: cache invalidation
test_cache_invalidate() {
  source "$CONFIG_LIB"
  export UMWELT_CACHE_ENABLED=1
  cache_init

  local key
  key=$(cache_key "git-context" "test")
  cache_set "$key" "data to invalidate"

  cache_invalidate "git-context"

  # Should not exist after invalidation
  ! cache_get "$key" &>/dev/null
}

# Test: cache clear
test_cache_clear() {
  source "$CONFIG_LIB"
  export UMWELT_CACHE_ENABLED=1
  cache_init

  cache_set "key1" "value1"
  cache_set "key2" "value2"

  cache_clear

  # Cache dir should be empty
  local count
  count=$(ls "$UMWELT_CACHE_DIR" 2>/dev/null | wc -l | tr -d ' ')
  [ "$count" -eq 0 ]
}
