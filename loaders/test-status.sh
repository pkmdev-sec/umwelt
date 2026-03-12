#!/usr/bin/env bash
# umwelt: test-status loader
# Detects test framework and reports last test results or runs quick tests
# Usage: umwelt test-status [--run|--last|--coverage|--json]
set -euo pipefail

# Source config and output systems
UMWELT_DIR="${UMWELT_DIR:-$HOME/.claude/umwelt}"
if [ -f "$UMWELT_DIR/lib/config.sh" ]; then
  source "$UMWELT_DIR/lib/config.sh"
fi
if [ -f "$UMWELT_DIR/lib/output.sh" ]; then
  source "$UMWELT_DIR/lib/output.sh"
fi

MODE="${1:-last}"
OUTPUT_FMT="${UMWELT_OUTPUT_FORMAT:-text}"
for arg in "$@"; do
  if [ "$arg" = "--json" ]; then OUTPUT_FMT="json"; fi
done

PROJECT_DIR="${UMWELT_PROJECT_DIR:-.}"
SCAN_DEPTH="${UMWELT_SCAN_DEPTH:-4}"

# ─── Detect Test Framework ───────────────────────────────────────
detect_framework() {
  if [ -f "$PROJECT_DIR/package.json" ]; then
    if grep -q '"vitest"' "$PROJECT_DIR/package.json" 2>/dev/null; then
      echo "vitest"
    elif grep -q '"jest"' "$PROJECT_DIR/package.json" 2>/dev/null; then
      echo "jest"
    elif grep -q '"mocha"' "$PROJECT_DIR/package.json" 2>/dev/null; then
      echo "mocha"
    elif grep -q '"test"' "$PROJECT_DIR/package.json" 2>/dev/null; then
      echo "npm-test"
    else
      echo "none"
    fi
  elif [ -f "$PROJECT_DIR/pytest.ini" ] || [ -f "$PROJECT_DIR/pyproject.toml" ] || [ -f "$PROJECT_DIR/setup.py" ]; then
    if command -v pytest &>/dev/null || command -v python3 &>/dev/null; then
      echo "pytest"
    else
      echo "none"
    fi
  elif [ -f "$PROJECT_DIR/Cargo.toml" ]; then
    echo "cargo-test"
  elif [ -f "$PROJECT_DIR/go.mod" ]; then
    echo "go-test"
  elif [ -f "$PROJECT_DIR/Package.swift" ]; then
    echo "swift-test"
  else
    echo "none"
  fi
}

FRAMEWORK=$(detect_framework)

# ─── Count Test Files ─────────────────────────────────────────────
count_tests() {
  case "$FRAMEWORK" in
    vitest|jest|mocha|npm-test)
      find "$PROJECT_DIR" -maxdepth "$SCAN_DEPTH" \( -name "*.test.*" -o -name "*.spec.*" -o -name "__tests__" \) -not -path "*/node_modules/*" 2>/dev/null | wc -l | tr -d ' '
      ;;
    pytest)
      find "$PROJECT_DIR" -maxdepth "$SCAN_DEPTH" \( -name "test_*.py" -o -name "*_test.py" \) -not -path "*/__pycache__/*" 2>/dev/null | wc -l | tr -d ' '
      ;;
    cargo-test)
      grep -r "#\[test\]" "$PROJECT_DIR/src" 2>/dev/null | wc -l | tr -d ' '
      ;;
    go-test)
      find "$PROJECT_DIR" -maxdepth "$SCAN_DEPTH" -name "*_test.go" 2>/dev/null | wc -l | tr -d ' '
      ;;
    swift-test)
      find "$PROJECT_DIR" -maxdepth "$SCAN_DEPTH" -name "*Tests.swift" 2>/dev/null | wc -l | tr -d ' '
      ;;
    *)
      echo "0"
      ;;
  esac
}

TEST_COUNT=$(count_tests)

# ─── Last Results Check ──────────────────────────────────────────
LAST_RESULT_FILE=""
LAST_RESULT_DATE=""

check_last_results() {
  local result_files=(
    "$PROJECT_DIR/.vitest-result.json"
    "$PROJECT_DIR/test-results.json"
    "$PROJECT_DIR/coverage/coverage-summary.json"
    "$PROJECT_DIR/junit.xml"
    "$PROJECT_DIR/.pytest_cache/v/cache/lastfailed"
    "$PROJECT_DIR/target/test-results"
  )

  for f in "${result_files[@]}"; do
    if [ -f "$f" ]; then
      LAST_RESULT_FILE="$f"
      LAST_RESULT_DATE=$(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$f" 2>/dev/null || stat -c '%y' "$f" 2>/dev/null | cut -d. -f1)
      return 0
    fi
  done
  return 1
}

LAST_FAILED_COUNT=""
check_last_results || true

# Check pytest last-failed cache
if [ "$FRAMEWORK" = "pytest" ] && [ -f "$PROJECT_DIR/.pytest_cache/v/cache/lastfailed" ]; then
  if command -v jq &>/dev/null; then
    LAST_FAILED_COUNT=$(jq 'length' "$PROJECT_DIR/.pytest_cache/v/cache/lastfailed" 2>/dev/null || echo "")
  else
    LAST_FAILED_COUNT=$(python3 -c "import json; d=json.load(open('$PROJECT_DIR/.pytest_cache/v/cache/lastfailed')); print(len(d))" 2>/dev/null || echo "")
  fi
fi

# ─── Coverage Data ────────────────────────────────────────────────
COVERAGE_JSON=""
if [ "$MODE" = "--coverage" ] && [ -f "$PROJECT_DIR/coverage/coverage-summary.json" ]; then
  if command -v jq &>/dev/null; then
    COVERAGE_JSON=$(jq -c '.total | {lines: .lines.pct, statements: .statements.pct, functions: .functions.pct, branches: .branches.pct} | with_entries(select(.value != null))' "$PROJECT_DIR/coverage/coverage-summary.json" 2>/dev/null || echo "")
  else
    COVERAGE_JSON=$(python3 -c "
import json
with open('$PROJECT_DIR/coverage/coverage-summary.json') as f:
    d = json.load(f)
total = d.get('total', {})
result = {}
for key in ['lines', 'statements', 'functions', 'branches']:
    if key in total:
        result[key] = total[key].get('pct', 0)
print(json.dumps(result))
" 2>/dev/null || echo "")
  fi
fi

# ─── Run Tests ────────────────────────────────────────────────────
RUN_OUTPUT=""
if [ "$MODE" = "--run" ] && [ "$FRAMEWORK" != "none" ]; then
  case "$FRAMEWORK" in
    vitest)     RUN_OUTPUT=$(cd "$PROJECT_DIR" && npx vitest run --reporter=verbose 2>&1 | tail -20) ;;
    jest)       RUN_OUTPUT=$(cd "$PROJECT_DIR" && npx jest --verbose 2>&1 | tail -20) ;;
    npm-test)   RUN_OUTPUT=$(cd "$PROJECT_DIR" && npm test 2>&1 | tail -20) ;;
    pytest)     RUN_OUTPUT=$(cd "$PROJECT_DIR" && python3 -m pytest --tb=short -q 2>&1 | tail -20) ;;
    cargo-test) RUN_OUTPUT=$(cd "$PROJECT_DIR" && cargo test 2>&1 | tail -20) ;;
    go-test)    RUN_OUTPUT=$(cd "$PROJECT_DIR" && go test ./... 2>&1 | tail -20) ;;
    swift-test) RUN_OUTPUT=$(cd "$PROJECT_DIR" && swift test 2>&1 | tail -20) ;;
  esac
fi

# ─── Output ──────────────────────────────────────────────────────
if [ "$OUTPUT_FMT" = "json" ]; then
  if command -v jq &>/dev/null; then
    jq -n \
      --arg framework "$FRAMEWORK" \
      --argjson test_count "$TEST_COUNT" \
      --arg result_file "$LAST_RESULT_FILE" \
      --arg result_date "$LAST_RESULT_DATE" \
      --arg failed_count "${LAST_FAILED_COUNT:-}" \
      --argjson has_coverage "$([ -f "$PROJECT_DIR/coverage/coverage-summary.json" ] && echo 'true' || echo 'false')" \
      --argjson coverage "${COVERAGE_JSON:-null}" \
      '{
        framework: $framework,
        test_file_count: $test_count,
        last_result_file: (if $result_file == "" then null else $result_file end),
        last_result_date: (if $result_date == "" then null else $result_date end),
        last_failed_count: (if $failed_count == "" then null else ($failed_count | tonumber) end),
        has_coverage: $has_coverage,
        coverage: $coverage
      }' 2>/dev/null || echo '{"error": "json generation failed"}'
  else
    python3 -c "
import json

data = {
    'framework': '$FRAMEWORK',
    'test_file_count': int('$TEST_COUNT'),
    'last_result_file': '$LAST_RESULT_FILE' or None,
    'last_result_date': '$LAST_RESULT_DATE' or None,
    'last_failed_count': int('${LAST_FAILED_COUNT:-0}' or '0') if '${LAST_FAILED_COUNT:-}' else None,
    'has_coverage': $([ -f \"$PROJECT_DIR/coverage/coverage-summary.json\" ] && echo 'True' || echo 'False'),
}

coverage_raw = '''$COVERAGE_JSON'''
if coverage_raw:
    try:
        data['coverage'] = json.loads(coverage_raw)
    except:
        pass

print(json.dumps(data, indent=2))
" 2>/dev/null || echo '{"error": "json serialization failed"}'
  fi
else
  text_header "TEST STATUS"
  text_kv "framework" "${FRAMEWORK}"

  if [ "$FRAMEWORK" = "none" ]; then
    echo "no test framework detected"
    text_footer "TEST STATUS"
    exit 0
  fi

  text_kv "test files" "${TEST_COUNT}"

  if [ "$MODE" = "--last" ] || [ "$MODE" = "last" ]; then
    if [ -n "$LAST_RESULT_FILE" ]; then
      text_kv "last results" "${LAST_RESULT_FILE} (${LAST_RESULT_DATE})"
    else
      text_kv "last results" "no cached results found"
    fi
    if [ -n "$LAST_FAILED_COUNT" ]; then
      text_kv "last failed" "${LAST_FAILED_COUNT} tests"
    fi
  fi

  if [ -n "$RUN_OUTPUT" ]; then
    text_subsection "running tests"
    echo "$RUN_OUTPUT"
  fi

  if [ "$MODE" = "--coverage" ]; then
    text_subsection "coverage"
    if [ -n "$COVERAGE_JSON" ]; then
      if command -v jq &>/dev/null; then
        echo "$COVERAGE_JSON" | jq -r 'to_entries | .[] | "  \(.key): \(.value)%"' 2>/dev/null || text_item "(could not parse coverage)"
      else
        python3 -c "
import json
d = json.loads('$COVERAGE_JSON')
for key, pct in d.items():
    print(f'  {key}: {pct}%')
" 2>/dev/null || text_item "(could not parse coverage)"
      fi
    else
      text_item "no coverage data found"
    fi
  fi

  text_footer "TEST STATUS"
fi
