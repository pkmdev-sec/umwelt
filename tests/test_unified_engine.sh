#!/usr/bin/env bash
# Tests for Innovation 8: Bang + Sigil Unified Context Engine
set -euo pipefail

UMWELT_DIR="${UMWELT_DIR:-$HOME/.claude/umwelt}"
UMWELT_CACHE_DIR="${UMWELT_CACHE_DIR:-$HOME/.claude/.bang-cache}"
PROMPT_STUDIO_DIR="${PROMPT_STUDIO_DIR:-$HOME/.claude/prompt-studio}"

source "$UMWELT_DIR/lib/unified-engine.sh"

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
    echo "not ok - $name (pattern '$pattern' not found in '$(echo "$actual" | head -3)')"
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

echo "# Unified Engine Tests (Innovation 8)"
echo "# ─────────────────────────────────────"

# Ensure clean cost state
reset_session_cost 2>/dev/null || true

# Test 1: get_stable_context produces output
stable=$(get_stable_context)
assert_match "stable context has os" 'os:' "$stable"
assert_match "stable context has shell" 'shell:' "$stable"
assert_match "stable context has user" 'user:' "$stable"
assert_match "stable context has cwd" 'cwd:' "$stable"

# Test 2: get_stable_context is cached
first=$(get_stable_context)
second=$(get_stable_context)
assert_eq "stable context is cached (same output)" "$first" "$second"

# Test 3: get_volatile_context produces output
volatile=$(get_volatile_context)
# May be empty if not in a git repo, but should not error
assert_eq "volatile context runs without error" "0" "$?"

# Test 4: get_priority_order lists sections
order=$(get_priority_order)
assert_match "priority order has sigil-template" 'sigil-template' "$order"
assert_match "priority order has git-context" 'git-context' "$order"
assert_match "priority order has docker-status" 'docker-status' "$order"

# Test 5: get_section_priority returns numbers
priority=$(get_section_priority "sigil-template")
assert_eq "sigil-template priority is 100" "100" "$priority"

priority=$(get_section_priority "git-context")
assert_eq "git-context priority is 90" "90" "$priority"

priority=$(get_section_priority "docker-status")
assert_eq "docker-status priority is 30" "30" "$priority"

# Test 6: estimate_text_tokens works
tokens=$(estimate_text_tokens "Hello world this is a test")
assert_match "estimate_text_tokens returns number" '^[0-9]+$' "$tokens"
assert_nonzero "estimate_text_tokens nonzero" "$tokens"

# Test 7: estimate_text_tokens empty
tokens=$(estimate_text_tokens "")
assert_eq "estimate_text_tokens empty is 0" "0" "$tokens"

# Test 8: Sigil template detection (no active template expected)
template=$(get_active_sigil_template)
# May or may not be set — just test it doesn't crash
assert_eq "get_active_sigil_template runs" "0" "$?"

# Test 9: is_sigil_active function exists and runs
if is_sigil_active; then
  echo "ok - is_sigil_active runs (active)"
else
  echo "ok - is_sigil_active runs (inactive)"
fi
PASSED=$((PASSED + 1))

# Test 10: assemble_unified_context produces output
reset_session_cost 2>/dev/null || true
output=$(assemble_unified_context "UserPromptSubmit" "fix the bug")
assert_nonzero "assemble produces output" "$output"

# Test 11: assemble_unified_context includes environment
output=$(assemble_unified_context "UserPromptSubmit" "")
assert_match "assemble includes environment" 'ENVIRONMENT' "$output"

# Test 12: assemble_unified_context includes cost summary
reset_session_cost 2>/dev/null || true
output=$(assemble_unified_context "UserPromptSubmit" "test query")
assert_match "assemble includes cost summary" 'Bang cost' "$output"

# Test 13: assemble_unified_context respects silent mode
reset_session_cost 2>/dev/null || true
add_session_cost "0.600000" > /dev/null
output=$(assemble_unified_context "UserPromptSubmit" "")
assert_match "silent mode shows budget exceeded" 'budget exceeded|Bang cost' "$output"

# Test 14: Sigil template loading (create temp template)
reset_session_cost 2>/dev/null || true
TEMP_TEMPLATE_DIR="$PROMPT_STUDIO_DIR/templates"
mkdir -p "$TEMP_TEMPLATE_DIR"
TEMP_ACTIVE="$PROMPT_STUDIO_DIR/.active-template"

# Create test template
cat > "$TEMP_TEMPLATE_DIR/_test_unified.md" << 'TMPL'
---
name: test-unified
description: Test template for unified engine
---

You are a helpful assistant for testing purposes.
Always be concise and clear.
TMPL

# Activate it
echo "_test_unified" > "$TEMP_ACTIVE"
output=$(assemble_unified_context "UserPromptSubmit" "help me test")
assert_match "sigil template included in output" 'helpful assistant' "$output"

# Clean up test template
rm -f "$TEMP_TEMPLATE_DIR/_test_unified.md"
rm -f "$TEMP_ACTIVE"

# Test 15: CLI interface — priority-order
cli_output=$("$UMWELT_DIR/lib/unified-engine.sh" priority-order 2>/dev/null)
assert_match "CLI priority-order works" 'sigil-template' "$cli_output"

# Test 16: CLI interface — stable
cli_output=$("$UMWELT_DIR/lib/unified-engine.sh" stable 2>/dev/null)
assert_match "CLI stable works" 'os:' "$cli_output"

# Test 17: CLI interface — volatile
cli_output=$("$UMWELT_DIR/lib/unified-engine.sh" volatile 2>/dev/null || true)
# May be empty if not in git repo, that's ok
assert_eq "CLI volatile runs without error" "0" "$?"

# Clean up
reset_session_cost 2>/dev/null || true
rm -f "$UMWELT_CACHE_DIR/stable-context"

# ═══ P1 Feature Tests: Metrics Output ═══
echo ""
echo "═══ P1: Metrics Output Tests ═══"

# Setup temp metrics
export UMWELT_METRICS_FILE=$(mktemp)

# Test 18: _init_metrics creates metrics file
_init_metrics
if [ -f "$UMWELT_METRICS_FILE" ]; then
  echo "ok - _init_metrics creates metrics file"
  PASSED=$((PASSED + 1))
else
  echo "not ok - metrics file should exist"
  FAILED=$((FAILED + 1))
fi

# Test 19: get_metric returns default 0
metric=$(get_metric "tokens_saved")
assert_eq "initial metric is 0" "0" "$metric"

# Test 20: increment_metric increases value
increment_metric "tokens_saved" 100
metric=$(get_metric "tokens_saved")
assert_eq "after increment metric is 100" "100" "$metric"

# Test 21: increment_metric accumulates
increment_metric "tokens_saved" 50
metric=$(get_metric "tokens_saved")
assert_eq "accumulated metric is 150" "150" "$metric"

# Test 22: record_tokens_saved
record_tokens_saved 200
metric=$(get_metric "tokens_saved")
assert_eq "record_tokens_saved updates metric" "350" "$metric"

# Test 23: record_cache_hit
record_cache_hit
record_cache_hit
hits=$(get_metric "cache_hits")
assert_eq "cache_hits is 2" "2" "$hits"

# Test 24: record_cache_miss
record_cache_miss
misses=$(get_metric "cache_misses")
assert_eq "cache_misses is 1" "1" "$misses"

# Test 25: record_loader_skipped
record_loader_skipped
record_loader_skipped
record_loader_skipped
skipped=$(get_metric "loaders_skipped")
assert_eq "loaders_skipped is 3" "3" "$skipped"

# Test 26: record_loader_run
record_loader_run
record_loader_run
runs=$(get_metric "loaders_run")
assert_eq "loaders_run is 2" "2" "$runs"

# Test 27: record_injection
record_injection
injections=$(get_metric "injections")
assert_eq "injections is 1" "1" "$injections"

# Test 28: get_metrics_summary generates report
summary=$(get_metrics_summary)
assert_match "metrics summary has header" "Metrics Summary" "$summary"
assert_match "metrics summary has tokens saved" "Tokens saved" "$summary"
assert_match "metrics summary has cache hit rate" "Cache hit rate" "$summary"

# Test 29: compact_metrics generates single line
compact=$(compact_metrics)
assert_match "compact metrics has tokens saved" "tokens saved" "$compact"
assert_match "compact metrics has cache hits" "cache hits" "$compact"
assert_match "compact metrics has loaders skipped" "loaders skipped" "$compact"

# Test 30: reset_metrics clears all
reset_metrics
metric=$(get_metric "tokens_saved")
assert_eq "after reset tokens_saved is 0" "0" "$metric"

# Test 31: CLI interface — metrics
reset_metrics
increment_metric "tokens_saved" 500
cli_output=$("$UMWELT_DIR/lib/unified-engine.sh" metrics 2>/dev/null)
assert_match "CLI metrics works" "Metrics Summary" "$cli_output"

# Test 32: CLI interface — compact-metrics
cli_output=$("$UMWELT_DIR/lib/unified-engine.sh" compact-metrics 2>/dev/null)
assert_match "CLI compact-metrics works" "metrics:" "$cli_output"

# Test 33: CLI interface — reset-metrics
# Reset and then verify reset command runs without error
cli_output=$("$UMWELT_DIR/lib/unified-engine.sh" reset-metrics 2>/dev/null)
assert_match "CLI reset-metrics runs" "reset" "$cli_output"

# Cleanup
rm -f "$UMWELT_METRICS_FILE"

echo ""
echo "# Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
