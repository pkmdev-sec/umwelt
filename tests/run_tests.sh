#!/usr/bin/env bash
# Comprehensive test runner for bang-framework
# Executes all test files and reports results in TAP format
set -euo pipefail

cd "$(dirname "$0")"
BANG_DIR="$(cd .. && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# TAP header
echo "TAP version 13"
echo ""

# Count total tests across all test files
TOTAL_TESTS=0
for test_file in test_*.sh; do
  [ -f "$test_file" ] || continue
  # Count test functions (lines starting with test_)
  count=$(grep -c "^test_" "$test_file" 2>/dev/null || echo "0")
  TOTAL_TESTS=$((TOTAL_TESTS + count))
done

echo "1..$TOTAL_TESTS"
echo ""

# Test execution tracking
TEST_NUM=0
PASSED=0
FAILED=0
SKIPPED=0
FAILED_TESTS=()

# Run all test files
for test_file in test_*.sh; do
  [ -f "$test_file" ] || continue

  echo "# ═══════════════════════════════════════════════════════════════"
  echo "# Running: $test_file"
  echo "# ═══════════════════════════════════════════════════════════════"

  # Extract and run each test function
  while IFS= read -r line; do
    if [[ "$line" =~ ^test_.*\(\) ]]; then
      test_name=$(echo "$line" | sed 's/().*//' | tr -d ' ')
      TEST_NUM=$((TEST_NUM + 1))

      # Run the test in a clean environment
      local exit_code=0
      local output=""

      # Capture both stdout and stderr
      if output=$(bash -c "source '$test_file' 2>&1 && $test_name" 2>&1); then
        echo "ok $TEST_NUM - $test_name"
        PASSED=$((PASSED + 1))
      else
        exit_code=$?
        echo "not ok $TEST_NUM - $test_name"
        FAILED=$((FAILED + 1))
        FAILED_TESTS+=("$test_file::$test_name")

        # Show error details
        if [ -n "$output" ]; then
          echo "#   Error output:"
          echo "$output" | sed 's/^/#     /'
        fi
        echo "#   Exit code: $exit_code"
      fi
    fi
  done < "$test_file"

  echo ""
done

# Summary section
echo "# ═══════════════════════════════════════════════════════════════"
echo "# TEST SUMMARY"
echo "# ═══════════════════════════════════════════════════════════════"
echo "#"
echo "# Total tests:  $TOTAL_TESTS"
echo -e "# ${GREEN}Passed:${NC}      $PASSED"
echo -e "# ${RED}Failed:${NC}      $FAILED"
echo -e "# ${YELLOW}Skipped:${NC}     $SKIPPED"
echo "#"

if [ "$FAILED" -gt 0 ]; then
  echo "# Failed tests:"
  for failed_test in "${FAILED_TESTS[@]}"; do
    echo "#   - $failed_test"
  done
  echo "#"
fi

# Calculate pass rate
if [ "$TOTAL_TESTS" -gt 0 ]; then
  PASS_RATE=$(awk "BEGIN {printf \"%.1f\", ($PASSED / $TOTAL_TESTS) * 100}")
  echo "# Pass rate:    ${PASS_RATE}%"
fi

echo "# ═══════════════════════════════════════════════════════════════"

# Exit with appropriate code
if [ "$FAILED" -gt 0 ]; then
  echo ""
  echo -e "${RED}${BOLD}TESTS FAILED${NC}"
  exit 1
else
  echo ""
  echo -e "${GREEN}${BOLD}ALL TESTS PASSED${NC}"
  exit 0
fi
