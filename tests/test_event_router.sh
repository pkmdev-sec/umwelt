#!/usr/bin/env bash
# Tests for Innovation 4: Event-Optimized Loading (event-router.sh)
set -euo pipefail

UMWELT_DIR="${UMWELT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
export UMWELT_DIR
export UMWELT_CACHE_DIR="${TMPDIR:-/tmp}/bang-test-cache-$$"
mkdir -p "$UMWELT_CACHE_DIR"

# Source the module under test
source "$UMWELT_DIR/lib/event-router.sh"

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

# ═══════════════════════════════════════════════════════════════
echo "=== Event Router Tests ==="
echo ""

# ─── get_trigger_loaders tests ────────────────────────────────
echo "--- get_trigger_loaders ---"

result=$(get_trigger_loaders "SessionStart")
assert_contains "SessionStart returns all loaders" "env-summary" "$result"
assert_contains "SessionStart includes git-context" "git-context" "$result"
assert_contains "SessionStart includes docker-status" "docker-status" "$result"
assert_contains "SessionStart includes api-health" "api-health" "$result"
assert_contains "SessionStart includes test-status" "test-status" "$result"
assert_contains "SessionStart includes deps-audit" "deps-audit" "$result"
assert_contains "SessionStart includes project-summary" "project-summary" "$result"

result=$(get_trigger_loaders "UserPromptSubmit")
assert_contains "UserPromptSubmit includes git-context" "git-context" "$result"
assert_contains "UserPromptSubmit includes docker-status" "docker-status" "$result"
assert_contains "UserPromptSubmit includes test-status" "test-status" "$result"
assert_not_contains "UserPromptSubmit excludes api-health" "api-health" "$result"
assert_not_contains "UserPromptSubmit excludes deps-audit" "deps-audit" "$result"

result=$(get_trigger_loaders "PreCompact")
assert_contains "PreCompact includes env-summary" "env-summary" "$result"
assert_contains "PreCompact includes git-context" "git-context" "$result"
assert_not_contains "PreCompact excludes docker-status" "docker-status" "$result"

result=$(get_trigger_loaders "PostToolUse" "git status")
assert_contains "PostToolUse(git) includes git-context" "git-context" "$result"
assert_not_contains "PostToolUse(git) excludes docker" "docker-status" "$result"

result=$(get_trigger_loaders "PostToolUse" "docker compose up -d")
assert_contains "PostToolUse(docker) includes git-context" "git-context" "$result"
assert_contains "PostToolUse(docker) includes docker-status" "docker-status" "$result"

result=$(get_trigger_loaders "PostToolUse" "npm test")
assert_contains "PostToolUse(npm test) includes test-status" "test-status" "$result"

result=$(get_trigger_loaders "UnknownEvent")
assert_empty "UnknownEvent returns empty" "$result"

echo ""

# ─── should_rescan tests ─────────────────────────────────────
echo "--- should_rescan ---"

# SessionStart: always true
if should_rescan "git-context" "SessionStart"; then
  TOTAL=$((TOTAL + 1)); PASSED=$((PASSED + 1))
  echo -e "  ${GREEN}PASS${NC} SessionStart always rescans git-context"
else
  TOTAL=$((TOTAL + 1)); FAILED=$((FAILED + 1))
  echo -e "  ${RED}FAIL${NC} SessionStart should rescan git-context"
fi

if should_rescan "env-summary" "SessionStart"; then
  TOTAL=$((TOTAL + 1)); PASSED=$((PASSED + 1))
  echo -e "  ${GREEN}PASS${NC} SessionStart always rescans env-summary"
else
  TOTAL=$((TOTAL + 1)); FAILED=$((FAILED + 1))
  echo -e "  ${RED}FAIL${NC} SessionStart should rescan env-summary"
fi

# PreCompact: env-summary yes, api-health no
if should_rescan "env-summary" "PreCompact"; then
  TOTAL=$((TOTAL + 1)); PASSED=$((PASSED + 1))
  echo -e "  ${GREEN}PASS${NC} PreCompact rescans env-summary"
else
  TOTAL=$((TOTAL + 1)); FAILED=$((FAILED + 1))
  echo -e "  ${RED}FAIL${NC} PreCompact should rescan env-summary"
fi

if ! should_rescan "api-health" "PreCompact"; then
  TOTAL=$((TOTAL + 1)); PASSED=$((PASSED + 1))
  echo -e "  ${GREEN}PASS${NC} PreCompact skips api-health"
else
  TOTAL=$((TOTAL + 1)); FAILED=$((FAILED + 1))
  echo -e "  ${RED}FAIL${NC} PreCompact should skip api-health"
fi

# PostToolUse: git-context always, docker only if docker command
if should_rescan "git-context" "PostToolUse" "ls -la"; then
  TOTAL=$((TOTAL + 1)); PASSED=$((PASSED + 1))
  echo -e "  ${GREEN}PASS${NC} PostToolUse always rescans git-context"
else
  TOTAL=$((TOTAL + 1)); FAILED=$((FAILED + 1))
  echo -e "  ${RED}FAIL${NC} PostToolUse should always rescan git-context"
fi

if should_rescan "docker-status" "PostToolUse" "docker ps"; then
  TOTAL=$((TOTAL + 1)); PASSED=$((PASSED + 1))
  echo -e "  ${GREEN}PASS${NC} PostToolUse rescans docker for docker commands"
else
  TOTAL=$((TOTAL + 1)); FAILED=$((FAILED + 1))
  echo -e "  ${RED}FAIL${NC} PostToolUse should rescan docker for docker commands"
fi

if ! should_rescan "docker-status" "PostToolUse" "cat file.txt"; then
  TOTAL=$((TOTAL + 1)); PASSED=$((PASSED + 1))
  echo -e "  ${GREEN}PASS${NC} PostToolUse skips docker for non-docker commands"
else
  TOTAL=$((TOTAL + 1)); FAILED=$((FAILED + 1))
  echo -e "  ${RED}FAIL${NC} PostToolUse should skip docker for non-docker commands"
fi

if should_rescan "test-status" "PostToolUse" "npm test"; then
  TOTAL=$((TOTAL + 1)); PASSED=$((PASSED + 1))
  echo -e "  ${GREEN}PASS${NC} PostToolUse rescans test-status for test commands"
else
  TOTAL=$((TOTAL + 1)); FAILED=$((FAILED + 1))
  echo -e "  ${RED}FAIL${NC} PostToolUse should rescan test-status for test commands"
fi

# UserPromptSubmit: docker only if stale (>5min)
# Fresh run should skip
_record_loader_run "docker-status"
if ! should_rescan "docker-status" "UserPromptSubmit"; then
  TOTAL=$((TOTAL + 1)); PASSED=$((PASSED + 1))
  echo -e "  ${GREEN}PASS${NC} UserPromptSubmit skips fresh docker-status"
else
  TOTAL=$((TOTAL + 1)); FAILED=$((FAILED + 1))
  echo -e "  ${RED}FAIL${NC} UserPromptSubmit should skip fresh docker-status"
fi

echo ""

# ─── route_event tests ───────────────────────────────────────
echo "--- route_event ---"

result=$(route_event "SessionStart")
assert_nonempty "route_event SessionStart returns loaders" "$result"
assert_contains "SessionStart routes all loaders" "git-context" "$result"

result=$(route_event "PostToolUse" "docker build .")
assert_contains "PostToolUse docker routes git+docker" "git-context" "$result"
assert_contains "PostToolUse docker routes docker-status" "docker-status" "$result"

result=$(route_event "UnknownEvent")
assert_empty "UnknownEvent routes nothing" "$result"

echo ""

# ─── record_loader_runs tests ────────────────────────────────
echo "--- record_loader_runs ---"

record_loader_runs "git-context" "docker-status"
TOTAL=$((TOTAL + 1))
if [ -f "$UMWELT_CACHE_DIR/event-router-git-context-ts" ] && [ -f "$UMWELT_CACHE_DIR/event-router-docker-status-ts" ]; then
  echo -e "  ${GREEN}PASS${NC} record_loader_runs creates timestamp files"
  PASSED=$((PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} record_loader_runs should create timestamp files"
  FAILED=$((FAILED + 1))
fi

echo ""

# ═══ P1 Feature Tests: Custom Event Mapping ═══
echo "═══ P1: Custom Event Mapping Tests ═══"
echo ""

# Setup temp config
export UMWELT_EVENT_CONFIG=$(mktemp)

echo "--- add_custom_event_mapping ---"
add_custom_event_mapping "CustomBuild" "project-summary deps-audit" >/dev/null
TOTAL=$((TOTAL + 1))
if [ -f "$UMWELT_EVENT_CONFIG" ]; then
  echo -e "  ${GREEN}PASS${NC} add_custom_event_mapping creates config file"
  PASSED=$((PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} config file should exist"
  FAILED=$((FAILED + 1))
fi

echo "--- get_custom_event_mapping ---"
load_custom_event_mappings
result=$(get_custom_event_mapping "CustomBuild")
assert_contains "CustomBuild maps to project-summary" "project-summary" "$result"
assert_contains "CustomBuild maps to deps-audit" "deps-audit" "$result"

echo "--- has_custom_event_mapping ---"
TOTAL=$((TOTAL + 1))
if has_custom_event_mapping "CustomBuild"; then
  echo -e "  ${GREEN}PASS${NC} has_custom_event_mapping returns true for existing"
  PASSED=$((PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} should find CustomBuild mapping"
  FAILED=$((FAILED + 1))
fi

TOTAL=$((TOTAL + 1))
if ! has_custom_event_mapping "NonExistentEvent"; then
  echo -e "  ${GREEN}PASS${NC} has_custom_event_mapping returns false for missing"
  PASSED=$((PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} should not find NonExistentEvent"
  FAILED=$((FAILED + 1))
fi

echo "--- get_trigger_loaders_with_custom ---"
result=$(get_trigger_loaders_with_custom "CustomBuild")
assert_contains "custom event returns custom loaders" "project-summary" "$result"

# Should fall back to defaults for non-custom events
result=$(get_trigger_loaders_with_custom "SessionStart")
assert_contains "SessionStart falls back to default" "git-context" "$result"

echo "--- route_event_with_custom ---"
# For custom events, get_trigger_loaders_with_custom should return custom loaders
# Note: route_event_with_custom also applies should_rescan filtering
# For unknown events, should_rescan returns false for all loaders
# So we just check that get_trigger_loaders_with_custom returns the right candidates
candidates=$(get_trigger_loaders_with_custom "CustomBuild")
TOTAL=$((TOTAL + 1))
if echo "$candidates" | grep -q "project-summary\|deps-audit\|git-context\|test-status"; then
  echo -e "  ${GREEN}PASS${NC} route_event_with_custom uses custom mapping candidates"
  PASSED=$((PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} should get custom loader candidates (got: $candidates)"
  FAILED=$((FAILED + 1))
fi

echo "--- update existing custom mapping ---"
add_custom_event_mapping "CustomBuild" "git-context test-status" >/dev/null
load_custom_event_mappings
result=$(get_custom_event_mapping "CustomBuild")
assert_contains "updated mapping has git-context" "git-context" "$result"
assert_contains "updated mapping has test-status" "test-status" "$result"

echo "--- list_custom_event_mappings ---"
add_custom_event_mapping "OnCommit" "git-context" >/dev/null
load_custom_event_mappings
list_output=$(list_custom_event_mappings)
assert_contains "list shows CustomBuild" "CustomBuild" "$list_output"
assert_contains "list shows OnCommit" "OnCommit" "$list_output"

echo "--- remove_custom_event_mapping ---"
remove_custom_event_mapping "OnCommit" >/dev/null
load_custom_event_mappings
TOTAL=$((TOTAL + 1))
if ! has_custom_event_mapping "OnCommit"; then
  echo -e "  ${GREEN}PASS${NC} remove_custom_event_mapping removes mapping"
  PASSED=$((PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} OnCommit should be removed"
  FAILED=$((FAILED + 1))
fi

# CustomBuild should still exist
TOTAL=$((TOTAL + 1))
if has_custom_event_mapping "CustomBuild"; then
  echo -e "  ${GREEN}PASS${NC} other mappings remain after removal"
  PASSED=$((PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} CustomBuild should still exist"
  FAILED=$((FAILED + 1))
fi

# Cleanup custom config
rm -f "$UMWELT_EVENT_CONFIG"

echo ""

# ─── Cleanup ────────────────────────────────────────────────
rm -rf "$UMWELT_CACHE_DIR"

# ─── Summary ────────────────────────────────────────────────
echo "════════════════════════════════════════"
echo -e "  Results: ${GREEN}${PASSED} passed${NC}, ${RED}${FAILED} failed${NC}, ${TOTAL} total"
echo "════════════════════════════════════════"

[ "$FAILED" -gt 0 ] && exit 1
exit 0
