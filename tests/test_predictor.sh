#!/usr/bin/env bash
# Tests for Innovation 9: Predictive Context Loading (predictor.sh)
set -euo pipefail

UMWELT_DIR="${UMWELT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
export UMWELT_DIR

# Source the module under test
source "$UMWELT_DIR/lib/predictor.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

PASSED=0
FAILED=0
TOTAL=0

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [ "$expected" = "$actual" ]; then
    echo -e "  ${GREEN}PASS${NC} $name"
    PASSED=$((PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $name"
    echo "    expected: '$expected'"
    echo "    actual:   '$actual'"
    FAILED=$((FAILED + 1))
  fi
}

assert_contains() {
  local name="$1" pattern="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$actual" | grep -qE "$pattern"; then
    echo -e "  ${GREEN}PASS${NC} $name"
    PASSED=$((PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $name (pattern '$pattern' not found)"
    echo "    actual: '$actual'"
    FAILED=$((FAILED + 1))
  fi
}

assert_not_contains() {
  local name="$1" pattern="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if ! echo "$actual" | grep -qE "$pattern"; then
    echo -e "  ${GREEN}PASS${NC} $name"
    PASSED=$((PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $name (pattern '$pattern' should NOT be present)"
    echo "    actual: '$actual'"
    FAILED=$((FAILED + 1))
  fi
}

assert_nonempty() {
  local name="$1" actual="$2"
  TOTAL=$((TOTAL + 1))
  if [ -n "$actual" ]; then
    echo -e "  ${GREEN}PASS${NC} $name"
    PASSED=$((PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $name (expected non-empty)"
    FAILED=$((FAILED + 1))
  fi
}

assert_empty() {
  local name="$1" actual="$2"
  TOTAL=$((TOTAL + 1))
  if [ -z "$actual" ]; then
    echo -e "  ${GREEN}PASS${NC} $name"
    PASSED=$((PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $name (expected empty, got '$actual')"
    FAILED=$((FAILED + 1))
  fi
}

assert_gt() {
  local name="$1" val="$2" threshold="$3"
  TOTAL=$((TOTAL + 1))
  if [ "$val" -gt "$threshold" ] 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC} $name ($val > $threshold)"
    PASSED=$((PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $name ($val should be > $threshold)"
    FAILED=$((FAILED + 1))
  fi
}

# ═══════════════════════════════════════════════════════════════
echo "=== Predictor Tests ==="
echo ""

# ─── extract_keywords tests ──────────────────────────────────
echo "--- extract_keywords ---"

result=$(extract_keywords "Fix the failing Git tests on main branch")
assert_contains "extracts 'git'" "git" "$result"
assert_contains "extracts 'fix'" "fix" "$result"
assert_contains "extracts 'branch'" "branch" "$result"
assert_contains "extracts 'tests'" "test" "$result"

result=$(extract_keywords "Deploy Docker containers to production")
assert_contains "extracts 'docker'" "docker" "$result"
assert_contains "extracts 'deploy'" "deploy" "$result"
assert_contains "extracts 'container'" "container" "$result"

result=$(extract_keywords "UPPERCASE and MiXeD CaSe")
assert_contains "lowercases 'uppercase'" "uppercase" "$result"
assert_contains "lowercases 'mixed'" "mixed" "$result"

result=$(extract_keywords "hello!!! world??? #special &chars")
assert_contains "strips punctuation: hello" "hello" "$result"
assert_contains "strips punctuation: world" "world" "$result"

result=$(extract_keywords "")
assert_empty "empty message returns empty" "$result"

echo ""

# ─── score_loader_relevance tests ────────────────────────────
echo "--- score_loader_relevance ---"

score=$(score_loader_relevance "git-context" "git branch commit merge")
assert_gt "git keywords score high for git-context" "$score" 50

score=$(score_loader_relevance "docker-status" "docker container compose deploy")
assert_gt "docker keywords score high for docker-status" "$score" 50

score=$(score_loader_relevance "test-status" "test jest coverage mock")
assert_gt "test keywords score high for test-status" "$score" 50

score=$(score_loader_relevance "env-summary" "error bug debug fix crash")
assert_gt "error keywords score high for env-summary" "$score" 50

score=$(score_loader_relevance "api-health" "api endpoint request http rest")
assert_gt "api keywords score high for api-health" "$score" 50

score=$(score_loader_relevance "deps-audit" "install dependency package npm audit")
assert_gt "deps keywords score high for deps-audit" "$score" 50

score=$(score_loader_relevance "project-summary" "build refactor architecture structure")
assert_gt "project keywords score high for project-summary" "$score" 50

# Cross-loader: git keywords should score low for docker-status
score=$(score_loader_relevance "docker-status" "git branch commit merge")
assert_eq "git keywords score 0 for docker-status" "0" "$score"

# Unknown loader
score=$(score_loader_relevance "nonexistent-loader" "git docker test")
assert_eq "unknown loader scores 0" "0" "$score"

# No matching keywords
score=$(score_loader_relevance "git-context" "banana orange apple fruit")
assert_eq "irrelevant keywords score 0" "0" "$score"

# Cap at 100
score=$(score_loader_relevance "git-context" "git branch commit merge push pull rebase cherry-pick stash checkout diff log blame tag reset amend")
TOTAL=$((TOTAL + 1))
if [ "$score" -le 100 ]; then
  echo -e "  ${GREEN}PASS${NC} score capped at 100 (got $score)"
  PASSED=$((PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} score should be capped at 100 (got $score)"
  FAILED=$((FAILED + 1))
fi

echo ""

# ─── filter_loaders tests ───────────────────────────────────
echo "--- filter_loaders ---"

result=$(filter_loaders "git-context docker-status test-status" "git branch commit" 20)
assert_contains "filter keeps git-context for git keywords" "git-context" "$result"
assert_not_contains "filter drops docker-status for git keywords" "docker-status" "$result"

result=$(filter_loaders "git-context docker-status api-health" "docker compose deploy" 20)
assert_contains "filter keeps docker-status for docker keywords" "docker-status" "$result"
assert_not_contains "filter drops git-context for docker keywords" "git-context" "$result"

# High threshold filters everything
result=$(filter_loaders "git-context docker-status" "git" 99)
assert_empty "high threshold filters most results" "$result"

echo ""

# ─── predict_needed_loaders tests ────────────────────────────
echo "--- predict_needed_loaders ---"

result=$(predict_needed_loaders "Fix the git merge conflict on the develop branch")
assert_contains "git message predicts git-context" "git-context" "$result"

result=$(predict_needed_loaders "Deploy the docker containers and check compose services")
assert_contains "docker message predicts docker-status" "docker-status" "$result"

result=$(predict_needed_loaders "Run the jest tests and check coverage")
assert_contains "test message predicts test-status" "test-status" "$result"

result=$(predict_needed_loaders "Debug the crash error in production, check the stack trace")
assert_contains "error message predicts env-summary" "env-summary" "$result"

result=$(predict_needed_loaders "Check the API endpoint health and http request status")
assert_contains "api message predicts api-health" "api-health" "$result"

result=$(predict_needed_loaders "Install npm dependencies and audit for vulnerabilities")
assert_contains "deps message predicts deps-audit" "deps-audit" "$result"

result=$(predict_needed_loaders "Refactor the project architecture and build system")
assert_contains "project message predicts project-summary" "project-summary" "$result"

# Multi-domain message
result=$(predict_needed_loaders "Fix the git merge then run the tests")
assert_contains "multi-domain includes git-context" "git-context" "$result"
assert_contains "multi-domain includes test-status" "test-status" "$result"

# Empty message
result=$(predict_needed_loaders "")
assert_empty "empty message returns nothing" "$result"

# Irrelevant message
result=$(predict_needed_loaders "Tell me a joke about bananas")
assert_empty "irrelevant message returns nothing" "$result"

# Ordering: higher-scoring loaders first
result=$(predict_needed_loaders "git commit merge branch push")
TOTAL=$((TOTAL + 1))
first_loader=$(echo "$result" | awk '{print $1}')
if [ "$first_loader" = "git-context" ]; then
  echo -e "  ${GREEN}PASS${NC} git-heavy message puts git-context first"
  PASSED=$((PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} git-heavy message should put git-context first (got: $first_loader)"
  FAILED=$((FAILED + 1))
fi

echo ""

# ─── Integration: min_score parameter ────────────────────────
echo "--- min_score parameter ---"

# With very low threshold, more loaders pass
result_low=$(predict_needed_loaders "git test" 5)
result_high=$(predict_needed_loaders "git test" 80)

low_count=$(echo "$result_low" | wc -w | tr -d ' ')
high_count=$(echo "$result_high" | wc -w | tr -d ' ')
# Handle empty result as 0 count
[ -z "$result_low" ] && low_count=0
[ -z "$result_high" ] && high_count=0

TOTAL=$((TOTAL + 1))
if [ "$low_count" -ge "$high_count" ]; then
  echo -e "  ${GREEN}PASS${NC} lower threshold returns >= loaders ($low_count >= $high_count)"
  PASSED=$((PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} lower threshold should return >= loaders ($low_count < $high_count)"
  FAILED=$((FAILED + 1))
fi

echo ""

# ─── Summary ────────────────────────────────────────────────
echo "════════════════════════════════════════"
echo -e "  Results: ${GREEN}${PASSED} passed${NC}, ${RED}${FAILED} failed${NC}, ${TOTAL} total"
echo "════════════════════════════════════════"

[ "$FAILED" -gt 0 ] && exit 1
exit 0
