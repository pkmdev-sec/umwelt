#!/usr/bin/env bash
# umwelt test runner
# Runs all tests in TAP format
set -euo pipefail

cd "$(dirname "$0")"
UMWELT_DIR="$(cd .. && pwd)"

# TAP header
echo "TAP version 13"

# Count total tests
TOTAL_TESTS=0
for test_file in test_*.sh; do
  [ -f "$test_file" ] || continue
  # Count test assertions in each file
  count=$(grep -c "^test_" "$test_file" 2>/dev/null || echo "0")
  TOTAL_TESTS=$((TOTAL_TESTS + count))
done

echo "1..$TOTAL_TESTS"

# Run all tests
TEST_NUM=0
PASSED=0
FAILED=0

for test_file in test_*.sh; do
  [ -f "$test_file" ] || continue

  echo "# Running $test_file"

  # Source the test file and run tests
  while IFS= read -r line; do
    if [[ "$line" =~ ^test_.*\(\) ]]; then
      test_name=$(echo "$line" | sed 's/().*//' | tr -d ' ')
      TEST_NUM=$((TEST_NUM + 1))

      # Run the test
      if bash -c "source $test_file && $test_name" &>/dev/null; then
        echo "ok $TEST_NUM - $test_name"
        PASSED=$((PASSED + 1))
      else
        echo "not ok $TEST_NUM - $test_name"
        FAILED=$((FAILED + 1))
      fi
    fi
  done < "$test_file"
done

# Summary
echo "# Tests: $TOTAL_TESTS, Passed: $PASSED, Failed: $FAILED"

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
