#!/usr/bin/env bash
# Tests for Innovation 7: Intelligent Loaders
set -euo pipefail

UMWELT_DIR="${UMWELT_DIR:-$HOME/.claude/umwelt}"
source "$UMWELT_DIR/lib/loader-intelligence.sh"

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

echo "# Loader Intelligence Tests (Innovation 7)"
echo "# ──────────────────────────────────────────"

# Test 1: is_loader_relevant — env-summary is always relevant
if is_loader_relevant "env-summary"; then
  assert_eq "env-summary is always relevant" "true" "true"
else
  assert_eq "env-summary is always relevant" "true" "false"
fi

# Test 2: is_loader_relevant — project-summary is always relevant
if is_loader_relevant "project-summary"; then
  assert_eq "project-summary is always relevant" "true" "true"
else
  assert_eq "project-summary is always relevant" "true" "false"
fi

# Test 3: is_loader_relevant — unknown loader defaults to relevant
if is_loader_relevant "unknown-loader-xyz"; then
  assert_eq "unknown loader defaults to relevant" "true" "true"
else
  assert_eq "unknown loader defaults to relevant" "true" "false"
fi

# Test 4: estimate_loader_tokens — env-summary returns a number
tokens=$(estimate_loader_tokens "env-summary")
assert_match "env-summary token estimate is numeric" '^[0-9]+$' "$tokens"
assert_nonzero "env-summary token estimate nonzero" "$tokens"

# Test 5: estimate_loader_tokens — git-context returns a number
tokens=$(estimate_loader_tokens "git-context")
assert_match "git-context token estimate is numeric" '^[0-9]+$' "$tokens"

# Test 6: estimate_loader_tokens — unknown loader returns default
tokens=$(estimate_loader_tokens "unknown-loader")
assert_eq "unknown loader token estimate is 100" "100" "$tokens"

# Test 7: predict_relevant_loaders — always includes git-context
predicted=$(predict_relevant_loaders "fix the bug")
assert_match "prediction always includes git-context" 'git-context' "$predicted"

# Test 8: predict_relevant_loaders — test message includes test-status
predicted=$(predict_relevant_loaders "fix the failing tests")
assert_match "test message includes test-status" 'test-status' "$predicted"

# Test 9: predict_relevant_loaders — docker message includes docker-status
predicted=$(predict_relevant_loaders "check docker containers")
assert_match "docker message includes docker-status" 'docker-status' "$predicted"

# Test 10: predict_relevant_loaders — api message includes api-health
predicted=$(predict_relevant_loaders "check the api endpoints")
assert_match "api message includes api-health" 'api-health' "$predicted"

# Test 11: predict_relevant_loaders — deps message includes deps-audit
predicted=$(predict_relevant_loaders "audit npm dependencies")
assert_match "deps message includes deps-audit" 'deps-audit' "$predicted"

# Test 12: predict_relevant_loaders — env message includes env-summary
predicted=$(predict_relevant_loaders "check environment versions")
assert_match "env message includes env-summary" 'env-summary' "$predicted"

# Test 13: format_loader_output — empty output produces nothing
result=$(format_loader_output "git-context" "")
assert_eq "empty output formats to nothing" "" "$result"

# Test 14: format_loader_output — docker not running filtered out
result=$(format_loader_output "docker-status" "=== DOCKER STATUS ===
docker: not running
=== END DOCKER STATUS ===")
assert_eq "docker not running filtered out" "" "$result"

# Test 15: format_loader_output — test none filtered out
result=$(format_loader_output "test-status" "=== TEST STATUS ===
no test framework detected
=== END TEST STATUS ===")
assert_eq "no test framework filtered out" "" "$result"

# Test 16: format_loader_output — git with conflicts adds relevance tag
result=$(format_loader_output "git-context" "=== GIT CONTEXT ===
staged: 0 files | unstaged: 2 files
CONFLICTS: 1 files
=== END GIT CONTEXT ===")
assert_match "conflicts add critical tag" 'critical' "$result"

# Test 17: format_loader_output — git with staged adds high tag
result=$(format_loader_output "git-context" "=== GIT CONTEXT ===
staged: 3 files | unstaged: 0 files
=== END GIT CONTEXT ===")
assert_match "staged adds high tag" 'high' "$result"

# Test 18: estimate_total_loader_tokens returns a number
total=$(estimate_total_loader_tokens "env-summary" "git-context")
assert_match "total estimate is numeric" '^[0-9]+$' "$total"
assert_nonzero "total estimate is nonzero" "$total"

# ═══ P1 Feature Tests: Loader Performance Timing ═══
echo ""
echo "═══ P1: Loader Performance Timing Tests ═══"

# Setup temp timing dir
export UMWELT_LOADER_TIMING_DIR=$(mktemp -d)
export UMWELT_LOADER_TIMEOUT=2
export UMWELT_LOADER_SLOW_THRESHOLD=1

# Test 19: record_loader_timing stores timing data
record_loader_timing "test-loader" 500
TIMING_FILE="$UMWELT_LOADER_TIMING_DIR/test-loader.times"
if [ -f "$TIMING_FILE" ]; then
  echo "ok - record_loader_timing creates timing file"
  PASSED=$((PASSED + 1))
else
  echo "not ok - timing file should exist"
  FAILED=$((FAILED + 1))
fi

# Test 20: get_loader_avg_time calculates average
record_loader_timing "avg-test" 1000
record_loader_timing "avg-test" 2000
record_loader_timing "avg-test" 3000
avg=$(get_loader_avg_time "avg-test")
assert_eq "average of 1000,2000,3000 is 2000" "2000" "$avg"

# Test 21: is_loader_slow detects slow loaders
record_loader_timing "slow-loader" 2500  # 2.5s > 1s threshold
if is_loader_slow "slow-loader"; then
  echo "ok - is_loader_slow detects slow loader"
  PASSED=$((PASSED + 1))
else
  echo "not ok - should detect slow loader"
  FAILED=$((FAILED + 1))
fi

# Test 22: is_loader_slow detects fast loaders
record_loader_timing "fast-loader" 100
if ! is_loader_slow "fast-loader"; then
  echo "ok - is_loader_slow correctly identifies fast loader"
  PASSED=$((PASSED + 1))
else
  echo "not ok - should not mark fast loader as slow"
  FAILED=$((FAILED + 1))
fi

# Test 23: filter_slow_loaders removes slow ones
loaders="fast-loader slow-loader"
filtered=$(filter_slow_loaders "$loaders")
assert_match "filtered has fast-loader" "fast-loader" "$filtered"
if ! echo "$filtered" | grep -q "slow-loader"; then
  echo "ok - filter_slow_loaders removes slow-loader"
  PASSED=$((PASSED + 1))
else
  echo "not ok - should filter out slow-loader"
  FAILED=$((FAILED + 1))
fi

# Test 24: get_loader_timing_report generates output
record_loader_timing "report-test" 1500
report=$(get_loader_timing_report)
if echo "$report" | grep -q "Loader Performance Report"; then
  echo "ok - get_loader_timing_report generates report"
  PASSED=$((PASSED + 1))
else
  echo "not ok - report should have header"
  FAILED=$((FAILED + 1))
fi

# Test 25: timing file keeps last 10 entries (rolling window)
for i in {1..15}; do
  record_loader_timing "rolling-test" $((i * 100))
done
count=$(wc -l < "$UMWELT_LOADER_TIMING_DIR/rolling-test.times" | tr -d ' ')
if [ "$count" -le 10 ]; then
  echo "ok - timing file keeps max 10 entries"
  PASSED=$((PASSED + 1))
else
  echo "not ok - timing file should have <=10 entries (has $count)"
  FAILED=$((FAILED + 1))
fi

# Cleanup
rm -rf "$UMWELT_LOADER_TIMING_DIR"

echo ""
echo "# Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
