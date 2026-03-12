#!/usr/bin/env bash
# Tests for Innovation 10: Diff-Based Injection Engine
set -euo pipefail

BANG_DIR="${BANG_DIR:-$HOME/.claude/bang-framework}"
BANG_DIFF_CACHE_DIR=$(mktemp -d)
export BANG_DIFF_CACHE_DIR

source "$BANG_DIR/lib/diff-engine.sh"

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

# Cleanup
rm -rf "$BANG_DIFF_CACHE_DIR"

echo ""
echo "════════════════════════════════════════"
echo -e "  Results: ${GREEN}${passed} passed${NC}, ${RED}${failed} failed${NC}, ${total} total"
echo "════════════════════════════════════════"

[ "$failed" -gt 0 ] && exit 1
exit 0
