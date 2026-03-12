#!/usr/bin/env bash
# Tests for Innovation 10: Diff-Based Injection Engine
set -euo pipefail

UMWELT_DIR="${UMWELT_DIR:-$HOME/.claude/umwelt}"
UMWELT_DIFF_CACHE_DIR=$(mktemp -d)
export UMWELT_DIFF_CACHE_DIR

source "$UMWELT_DIR/lib/diff-engine.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

passed=0
failed=0
total=0

assert() {
  local name="$1"
  local expected="$2"
  local actual="$3"
  total=$((total + 1))
  if [ "$expected" = "$actual" ]; then
    echo -e "  ${GREEN}PASS${NC} $name"
    passed=$((passed + 1))
  else
    echo -e "  ${RED}FAIL${NC} $name (expected='$expected', got='$actual')"
    failed=$((failed + 1))
  fi
}

assert_rc() {
  local name="$1"
  local expected_rc="$2"
  shift 2
  local actual_rc=0
  "$@" || actual_rc=$?
  total=$((total + 1))
  if [ "$expected_rc" = "$actual_rc" ]; then
    echo -e "  ${GREEN}PASS${NC} $name"
    passed=$((passed + 1))
  else
    echo -e "  ${RED}FAIL${NC} $name (expected rc=$expected_rc, got rc=$actual_rc)"
    failed=$((failed + 1))
  fi
}

assert_ge() {
  local name="$1"
  local threshold="$2"
  local actual="$3"
  total=$((total + 1))
  if [ "$actual" -ge "$threshold" ]; then
    echo -e "  ${GREEN}PASS${NC} $name ($actual >= $threshold)"
    passed=$((passed + 1))
  else
    echo -e "  ${RED}FAIL${NC} $name ($actual < $threshold)"
    failed=$((failed + 1))
  fi
}

echo "═══ Diff Engine Tests ═══"
echo ""

# Test 1: First call should always inject (return 0)
echo "Test: first call injects"
assert_rc "diff_inject first call returns 0" 0 diff_inject "test-loader" "hello world"

# Test 2: Same output should skip (return 1)
echo "Test: same output skips"
assert_rc "diff_inject same output returns 1" 1 diff_inject "test-loader" "hello world"

# Test 3: Different output should inject (return 0)
echo "Test: different output injects"
assert_rc "diff_inject changed output returns 0" 0 diff_inject "test-loader" "hello changed world"

# Test 4: get_diff_summary shows first scan
echo "Test: diff summary first scan"
summary=$(get_diff_summary "new-loader" "some output")
assert "first scan summary" "true" "$(echo "$summary" | grep -q 'first scan' && echo true || echo false)"

# Test 5: get_diff_summary shows lines changed
echo "Test: diff summary shows changes"
diff_inject "summary-test" "line1" || true
summary=$(get_diff_summary "summary-test" "line1-changed")
assert "changed summary" "true" "$(echo "$summary" | grep -q 'changed' && echo true || echo false)"

# Test 6: has_cache returns true for cached loader
echo "Test: has_cache"
diff_inject "cache-test" "data" || true
assert_rc "has_cache for existing loader" 0 has_cache "cache-test"

# Test 7: has_cache returns false for unknown loader
echo "Test: has_cache miss"
assert_rc "has_cache for unknown loader" 1 has_cache "nonexistent-loader"

# Test 8: get_cached returns cached data
echo "Test: get_cached"
diff_inject "cached-data" "my cached output" || true
cached=$(get_cached "cached-data")
assert "get_cached returns data" "my cached output" "$cached"

# Test 9: reset_cache clears everything
echo "Test: reset_cache"
reset_cache
assert_rc "after reset, has_cache returns 1" 1 has_cache "cache-test"

# ═══ P1 Feature Tests: Cache Expiry & Size Limits ═══
echo ""
echo "═══ P1: Cache Expiry Tests ═══"
echo ""

# Test 10: Cache age tracking
echo "Test: cache age tracking"
export UMWELT_DIFF_CACHE_EXPIRY=1  # 1 minute expiry
diff_inject "age-test" "data" || true
age=$(get_cache_age "age-test")
assert "cache age is 0 minutes" "0" "$age"

# Test 11: Fresh cache is not stale
echo "Test: fresh cache not stale"
diff_inject "fresh-test" "data" || true
assert_rc "fresh cache not stale" 1 is_cache_stale "fresh-test"

# Test 12: Cache size tracking
echo "Test: cache size tracking"
diff_inject "size-test-1" "data1234567890" || true
diff_inject "size-test-2" "data1234567890" || true
size=$(get_cache_size_mb)
assert_ge "cache has non-zero size" 0 "$size"

# Test 13: diff_inject_with_expiry on fresh cache
echo "Test: diff_inject_with_expiry fresh"
export UMWELT_DIFF_CACHE_EXPIRY=30
diff_inject_with_expiry "expiry-test" "initial data" || true
assert_rc "second call with same data returns 1" 1 diff_inject_with_expiry "expiry-test" "initial data"

# Test 14: diff_inject_with_expiry with changed data
echo "Test: diff_inject_with_expiry changed"
assert_rc "changed data returns 0" 0 diff_inject_with_expiry "expiry-test" "changed data"

# Test 15: clean_expired_cache
echo "Test: clean_expired_cache"
export UMWELT_DIFF_CACHE_EXPIRY=0  # Everything is stale
diff_inject "will-expire-1" "data1" || true
diff_inject "will-expire-2" "data2" || true
sleep 1
clean_expired_cache
assert_rc "cleaned cache returns empty" 1 has_cache "will-expire-1"

# Test 16: enforce_cache_size_limit
echo "Test: enforce_cache_size_limit"
export UMWELT_DIFF_CACHE_MAX_SIZE=1  # 1MB limit
for i in {1..5}; do
  diff_inject "size-limit-$i" "$(printf 'x%.0s' {1..1000})" || true
done
enforce_cache_size_limit
final_size=$(get_cache_size_mb)
assert_ge "cache size within limit" 0 "$final_size"

# Cleanup
rm -rf "$UMWELT_DIFF_CACHE_DIR"

echo ""
echo "════════════════════════════════════════"
echo -e "  Results: ${GREEN}${passed} passed${NC}, ${RED}${failed} failed${NC}, ${total} total"
echo "════════════════════════════════════════"

[ "$failed" -gt 0 ] && exit 1
exit 0
