#!/usr/bin/env bash
# Tests for Innovation 6: Cost-Conscious Scanning
set -euo pipefail

UMWELT_DIR="${UMWELT_DIR:-$HOME/.claude/umwelt}"
source "$UMWELT_DIR/lib/cost-tracker.sh"

PASSED=0
FAILED=0

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "ok - $name"
    PASSED=$((PASSED + 1))
  else
    echo "not ok - $name (expected '$expected', got '$actual')"
    FAILED=$((FAILED + 1))
  fi
}

assert_match() {
  local name="$1" pattern="$2" actual="$3"
  if echo "$actual" | grep -qE "$pattern"; then
    echo "ok - $name"
    PASSED=$((PASSED + 1))
  else
    echo "not ok - $name (pattern '$pattern' not found in '$actual')"
    FAILED=$((FAILED + 1))
  fi
}

assert_nonzero() {
  local name="$1" actual="$2"
  if [ -n "$actual" ] && [ "$actual" != "0" ]; then
    echo "ok - $name"
    PASSED=$((PASSED + 1))
  else
    echo "not ok - $name (expected nonzero, got '$actual')"
    FAILED=$((FAILED + 1))
  fi
}

echo "# Cost Tracker Tests (Innovation 6)"
echo "# ─────────────────────────────────"

# Test 1: estimate_tokens returns a number
test_tokens=$(estimate_tokens "Hello world, this is a test string for token estimation")
assert_match "estimate_tokens returns number" '^[0-9]+$' "$test_tokens"
assert_nonzero "estimate_tokens is nonzero" "$test_tokens"

# Test 2: estimate_tokens handles empty input
empty_tokens=$(estimate_tokens "")
assert_eq "estimate_tokens empty returns 0" "0" "$empty_tokens"

# Test 3: estimate_injection_cost returns a decimal
cost=$(estimate_injection_cost "This is a test prompt that should have a small cost")
assert_match "estimate_injection_cost returns decimal" '^[0-9]+\.[0-9]+$' "$cost"

# Test 4: Session cost reset
reset_session_cost
session_cost=$(get_session_cost)
assert_eq "reset_session_cost zeros out" "0.000000" "$session_cost"

# Test 5: get_cost_profile after reset is full
reset_session_cost
profile=$(get_cost_profile)
assert_eq "cost profile after reset is full" "full" "$profile"

# Test 6: should_inject after reset returns true
reset_session_cost
if should_inject; then
  assert_eq "should_inject after reset" "true" "true"
else
  assert_eq "should_inject after reset" "true" "false"
fi

# Test 7: add_session_cost accumulates
reset_session_cost
add_session_cost "0.050000" > /dev/null
new_cost=$(get_session_cost)
assert_match "add_session_cost accumulates" '^0\.05' "$new_cost"

# Test 8: get_cost_profile changes with accumulation
reset_session_cost
add_session_cost "0.120000" > /dev/null
profile=$(get_cost_profile)
assert_eq "cost profile at 0.12 is reduced" "reduced" "$profile"

# Test 9: get_cost_profile minimal threshold
reset_session_cost
add_session_cost "0.300000" > /dev/null
profile=$(get_cost_profile)
assert_eq "cost profile at 0.30 is minimal" "minimal" "$profile"

# Test 10: get_cost_profile silent threshold
reset_session_cost
add_session_cost "0.600000" > /dev/null
profile=$(get_cost_profile)
assert_eq "cost profile at 0.60 is silent" "silent" "$profile"

# Test 11: should_inject returns false when silent
reset_session_cost
add_session_cost "0.600000" > /dev/null
if should_inject; then
  assert_eq "should_inject when silent" "false" "true"
else
  assert_eq "should_inject when silent" "false" "false"
fi

# Test 12: get_allowed_loaders full mode
allowed=$(get_allowed_loaders "full")
assert_match "full mode includes git-context" 'git-context' "$allowed"
assert_match "full mode includes docker-status" 'docker-status' "$allowed"

# Test 13: get_allowed_loaders reduced mode
allowed=$(get_allowed_loaders "reduced")
assert_match "reduced mode includes git-context" 'git-context' "$allowed"

# Test 14: get_allowed_loaders minimal mode
allowed=$(get_allowed_loaders "minimal")
assert_match "minimal mode includes git-context" 'git-context' "$allowed"

# Test 15: get_allowed_loaders silent mode
allowed=$(get_allowed_loaders "silent")
assert_eq "silent mode has no loaders" "" "$allowed"

# Test 16: format_cost_summary produces output
reset_session_cost
summary=$(format_cost_summary)
assert_match "format_cost_summary has Bang cost" 'Bang cost' "$summary"
assert_match "format_cost_summary has Budget" 'Budget' "$summary"
assert_match "format_cost_summary has Mode" 'Mode' "$summary"

# Test 17: get_budget_pct returns a number
reset_session_cost
pct=$(get_budget_pct)
assert_match "get_budget_pct returns number" '^[0-9]+$' "$pct"

# Test 18: track_injection returns summary
reset_session_cost
result=$(track_injection "Small test injection")
assert_match "track_injection returns summary" 'Bang cost' "$result"

# Clean up
reset_session_cost

echo ""
echo "# Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
