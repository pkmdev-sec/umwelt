#!/usr/bin/env bash
# Tests for Innovation 1: Token-Aware Profiling
set -euo pipefail

UMWELT_DIR="${UMWELT_DIR:-$HOME/.claude/umwelt}"
UMWELT_DIFF_CACHE_DIR=$(mktemp -d)
export UMWELT_DIFF_CACHE_DIR
export UMWELT_TOKEN_BUDGET=1000

source "$UMWELT_DIR/lib/token-budget.sh"

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

echo "═══ Token Budget Tests ═══"
echo ""

# Test 1: estimate_tokens basic
echo "Test: estimate_tokens"
tokens=$(estimate_tokens "hello world!!")  # 13 chars / 4 = 3
assert_ge "estimate_tokens returns >0" 1 "$tokens"

# Test 2: estimate_tokens rough accuracy
echo "Test: estimate_tokens accuracy"
# 400 chars should be ~100 tokens
text=$(printf 'a%.0s' {1..400})
tokens=$(estimate_tokens "$text")
assert "400 chars = 100 tokens" "100" "$tokens"

# Test 3: Initial session tokens = 0
echo "Test: initial session tokens"
reset_token_count
tokens=$(get_session_tokens)
assert "initial session tokens" "0" "$tokens"

# Test 4: track_tokens accumulates
echo "Test: track_tokens accumulates"
reset_token_count
track_tokens "$(printf 'a%.0s' {1..400})" >/dev/null  # +100 tokens
track_tokens "$(printf 'b%.0s' {1..200})" >/dev/null  # +50 tokens
tokens=$(get_session_tokens)
assert "accumulated tokens" "150" "$tokens"

# Test 5: check_token_budget returns remaining
echo "Test: check_token_budget"
reset_token_count
track_tokens "$(printf 'a%.0s' {1..400})" >/dev/null  # 100 tokens used
remaining=$(check_token_budget)
assert "remaining budget" "900" "$remaining"

# Test 6: get_budget_percentage
echo "Test: get_budget_percentage"
reset_token_count
track_tokens "$(printf 'a%.0s' {1..2000})" >/dev/null  # 500 tokens = 50%
pct=$(get_budget_percentage)
assert "50% used" "50" "$pct"

# Test 7: should_downgrade at <50% — no change
echo "Test: should_downgrade under 50%"
reset_token_count
track_tokens "$(printf 'a%.0s' {1..800})" >/dev/null  # 200 tokens = 20%
recommended=$(should_downgrade "debug")
assert "under 50%: no downgrade" "debug" "$recommended"

# Test 8: should_downgrade at 50% — debug→dev
echo "Test: should_downgrade at 50%"
reset_token_count
track_tokens "$(printf 'a%.0s' {1..2000})" >/dev/null  # 500 = 50%
recommended=$(should_downgrade "debug")
assert "at 50%: debug->dev" "dev" "$recommended"

# Test 9: should_downgrade at 75% — any→minimal
echo "Test: should_downgrade at 75%"
reset_token_count
track_tokens "$(printf 'a%.0s' {1..3000})" >/dev/null  # 750 = 75%
recommended=$(should_downgrade "dev")
assert "at 75%: dev->minimal" "minimal" "$recommended"

# Test 10: should_downgrade at 90% — any→silent
echo "Test: should_downgrade at 90%"
reset_token_count
track_tokens "$(printf 'a%.0s' {1..3600})" >/dev/null  # 900 = 90%
recommended=$(should_downgrade "minimal")
assert "at 90%: minimal->silent" "silent" "$recommended"

# Test 11: budget_status_line format
echo "Test: budget_status_line"
reset_token_count
track_tokens "$(printf 'a%.0s' {1..400})" >/dev/null  # 100 tokens
status=$(budget_status_line)
has_tokens=$(echo "$status" | grep -q 'tokens:' && echo true || echo false)
assert "status line has tokens:" "true" "$has_tokens"

# Test 12: reset_token_count
echo "Test: reset_token_count"
track_tokens "some data" >/dev/null
reset_token_count
tokens=$(get_session_tokens)
assert "after reset" "0" "$tokens"

# ═══ P1 Feature Tests: Visual Budget Bar ═══
echo ""
echo "═══ P1: Visual Budget Bar Tests ═══"
echo ""

# Test 13: visual_budget_bar generates output
echo "Test: visual_budget_bar output"
reset_token_count
track_tokens "$(printf 'a%.0s' {1..2000})" >/dev/null  # 500 = 50%
bar=$(visual_budget_bar 20)
has_bar=$(echo "$bar" | grep -q '█' && echo true || echo false)
assert "visual bar contains filled blocks" "true" "$has_bar"

# Test 14: visual_budget_bar shows percentage
echo "Test: visual_budget_bar percentage"
reset_token_count
track_tokens "$(printf 'a%.0s' {1..2000})" >/dev/null  # 500 = 50%
bar=$(visual_budget_bar 20)
has_pct=$(echo "$bar" | grep -q '50%' && echo true || echo false)
assert "visual bar shows 50%" "true" "$has_pct"

# Test 15: compact_budget_bar format
echo "Test: compact_budget_bar"
reset_token_count
track_tokens "$(printf 'a%.0s' {1..800})" >/dev/null  # 200 = 20%
compact=$(compact_budget_bar 10)
has_bracket=$(echo "$compact" | grep -q '\[' && echo true || echo false)
assert "compact bar has brackets" "true" "$has_bracket"

# Test 16: budget_status_with_bar includes recommendation
echo "Test: budget_status_with_bar recommendations"
reset_token_count
track_tokens "$(printf 'a%.0s' {1..3600})" >/dev/null  # 900 = 90%
status=$(budget_status_with_bar 20)
has_warning=$(echo "$status" | grep -qi 'warning\|notice' && echo true || echo false)
assert "status has warning at 90%" "true" "$has_warning"

# Test 17: visual_budget_bar different widths
echo "Test: visual_budget_bar custom width"
reset_token_count
track_tokens "$(printf 'a%.0s' {1..2000})" >/dev/null  # 500 = 50%
bar_40=$(visual_budget_bar 40)
bar_10=$(visual_budget_bar 10)
len_40=$(echo "$bar_40" | head -1 | wc -c)
len_10=$(echo "$bar_10" | head -1 | wc -c)
assert_ge "bar width 40 > bar width 10" "$len_10" "$len_40"

# Test 18: visual_budget_bar at 0%
echo "Test: visual_budget_bar at 0%"
reset_token_count
bar=$(visual_budget_bar 20)
has_empty=$(echo "$bar" | grep -q '░' && echo true || echo false)
assert "empty bar has empty blocks" "true" "$has_empty"

# Test 19: visual_budget_bar at 100%
echo "Test: visual_budget_bar at 100%"
reset_token_count
track_tokens "$(printf 'a%.0s' {1..4000})" >/dev/null  # 1000 = 100%
bar=$(visual_budget_bar 20)
has_filled=$(echo "$bar" | grep -q '█' && echo true || echo false)
assert "full bar has filled blocks" "true" "$has_filled"

# Cleanup
rm -rf "$UMWELT_DIFF_CACHE_DIR"

echo ""
echo "════════════════════════════════════════"
echo -e "  Results: ${GREEN}${passed} passed${NC}, ${RED}${failed} failed${NC}, ${total} total"
echo "════════════════════════════════════════"

[ "$failed" -gt 0 ] && exit 1
exit 0
