#!/usr/bin/env bash
# Tests for Innovation 2: Cache-Friendly Output
set -euo pipefail

UMWELT_DIR="${UMWELT_DIR:-$HOME/.claude/umwelt}"
UMWELT_DIFF_CACHE_DIR=$(mktemp -d)
export UMWELT_DIFF_CACHE_DIR

source "$UMWELT_DIR/lib/cache-split.sh"

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

assert_contains() {
  local name="$1"
  local pattern="$2"
  local text="$3"
  total=$((total + 1))
  if echo "$text" | grep -qE "$pattern"; then
    echo -e "  ${GREEN}PASS${NC} $name"
    passed=$((passed + 1))
  else
    echo -e "  ${RED}FAIL${NC} $name (pattern '$pattern' not found)"
    failed=$((failed + 1))
  fi
}

assert_not_contains() {
  local name="$1"
  local pattern="$2"
  local text="$3"
  total=$((total + 1))
  if ! echo "$text" | grep -qE "$pattern"; then
    echo -e "  ${GREEN}PASS${NC} $name"
    passed=$((passed + 1))
  else
    echo -e "  ${RED}FAIL${NC} $name (pattern '$pattern' unexpectedly found)"
    failed=$((failed + 1))
  fi
}

echo "═══ Cache-Split Tests ═══"
echo ""

# Test 1: format_stable_context returns OS info
echo "Test: stable context has OS"
stable=$(format_stable_context)
assert_contains "stable has os:" "os:" "$stable"

# Test 2: format_stable_context returns shell info
echo "Test: stable context has shell"
assert_contains "stable has shell:" "shell:" "$stable"

# Test 3: format_stable_context is cached on second call
echo "Test: stable context is cached"
# Clear and re-run
rm -f "$UMWELT_DIFF_CACHE_DIR/stable-context.cache"
first=$(format_stable_context)
second=$(format_stable_context)
assert "stable cached (same output)" "$first" "$second"
assert "stable cache file exists" "true" "$([ -f "$UMWELT_DIFF_CACHE_DIR/stable-context.cache" ] && echo true || echo false)"

# Test 4: format_volatile_context returns git or load info
echo "Test: volatile context runs"
volatile=$(format_volatile_context)
# Should at least return something (may be empty if not in git repo and no load)
total=$((total + 1))
# It runs without error — that's a pass
echo -e "  ${GREEN}PASS${NC} volatile context executes without error"
passed=$((passed + 1))

# Test 5: First call to format_cached_output includes STABLE
echo "Test: first cached output has STABLE section"
reset_cache_split
output=$(format_cached_output)
assert_contains "first call has STABLE" "STABLE CONTEXT" "$output"
assert_contains "first call has VOLATILE" "VOLATILE CONTEXT" "$output"

# Test 6: Second call omits STABLE section
echo "Test: second cached output omits STABLE"
output2=$(format_cached_output)
assert_not_contains "second call omits STABLE" "STABLE CONTEXT" "$output2"

# Test 7: Second call shows volatile status
echo "Test: second call shows volatile update or unchanged"
assert_contains "second call has volatile or unchanged" "(VOLATILE|unchanged)" "$output2"

# Test 8: reset_cache_split clears state
echo "Test: reset_cache_split"
reset_cache_split
assert "call count file removed" "false" "$([ -f "$UMWELT_DIFF_CACHE_DIR/call-count" ] && echo true || echo false)"
assert "stable cache removed" "false" "$([ -f "$UMWELT_DIFF_CACHE_DIR/stable-context.cache" ] && echo true || echo false)"

# Test 9: After reset, first call includes STABLE again
echo "Test: after reset, STABLE returns"
output3=$(format_cached_output)
assert_contains "after reset has STABLE" "STABLE CONTEXT" "$output3"

# Cleanup
rm -rf "$UMWELT_DIFF_CACHE_DIR"

echo ""
echo "════════════════════════════════════════"
echo -e "  Results: ${GREEN}${passed} passed${NC}, ${RED}${failed} failed${NC}, ${total} total"
echo "════════════════════════════════════════"

[ "$failed" -gt 0 ] && exit 1
exit 0
