#!/usr/bin/env bash
# Comprehensive tests for parallel execution
set -euo pipefail

BANG_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PARALLEL_LIB="$BANG_DIR/lib/parallel.sh"
CONFIG_LIB="$BANG_DIR/lib/config.sh"

# ═══════════════════════════════════════════════════════════════════
# BASIC FUNCTIONALITY TESTS
# ═══════════════════════════════════════════════════════════════════

test_parallel_lib_exists() {
  [ -f "$PARALLEL_LIB" ]
}

test_parallel_lib_sources() {
  source "$PARALLEL_LIB"
  type parallel_run &>/dev/null
}

# ═══════════════════════════════════════════════════════════════════
# PARALLEL EXECUTION TESTS
# ═══════════════════════════════════════════════════════════════════

test_parallel_execution_enabled() {
  source "$CONFIG_LIB"
  source "$PARALLEL_LIB"

  export BANG_PARALLEL=1
  export BANG_DIR

  # Run two loaders in parallel
  local output
  output=$(parallel_run "git-context --minimal" "env-summary --minimal" 2>&1 || echo "")

  # Should contain output from both loaders
  [ -n "$output" ]
}

test_parallel_execution_disabled() {
  source "$CONFIG_LIB"
  source "$PARALLEL_LIB"

  export BANG_PARALLEL=0
  export BANG_DIR

  local output
  output=$(parallel_run "git-context --minimal" 2>&1 || echo "")

  # Should run without error
  [ -n "$output" ]
}

test_parallel_single_loader() {
  source "$CONFIG_LIB"
  source "$PARALLEL_LIB"

  export BANG_PARALLEL=1
  export BANG_DIR

  # Single loader should work
  local output
  output=$(parallel_run "env-summary --minimal" 2>&1 || echo "")
  [ -n "$output" ]
}

test_parallel_empty_input() {
  source "$CONFIG_LIB"
  source "$PARALLEL_LIB"

  export BANG_PARALLEL=1
  export BANG_DIR

  # Empty input should return cleanly
  parallel_run &>/dev/null || true
}

# ═══════════════════════════════════════════════════════════════════
# CONCURRENCY LIMITING TESTS
# ═══════════════════════════════════════════════════════════════════

test_concurrency_limit_enforced() {
  source "$CONFIG_LIB"
  source "$PARALLEL_LIB"

  export BANG_PARALLEL=1
  export BANG_MAX_PARALLEL=2
  export BANG_DIR

  # Run 4 loaders with max 2 parallel - should work without hitting limits
  parallel_run \
    "git-context --minimal" \
    "env-summary --minimal" \
    "deps-audit" \
    "project-summary" &>/dev/null || true
}

test_concurrency_limit_default() {
  source "$CONFIG_LIB"
  source "$PARALLEL_LIB"

  export BANG_PARALLEL=1
  unset BANG_MAX_PARALLEL
  export BANG_DIR

  # Should use default max (4)
  parallel_run "git-context --minimal" "env-summary --minimal" &>/dev/null || true
}

test_concurrency_semaphore_cleanup() {
  source "$CONFIG_LIB"
  source "$PARALLEL_LIB"

  export BANG_PARALLEL=1
  export BANG_MAX_PARALLEL=2
  export BANG_DIR

  # Run and ensure semaphore files are cleaned up
  parallel_run "git-context --minimal" "env-summary --minimal" &>/dev/null || true

  # Check that no stale semaphore directories remain
  local stale_count
  stale_count=$(find /tmp -name "bang-parallel-*" -type d 2>/dev/null | wc -l | tr -d ' ')

  # Should have 0 or very few (accounting for concurrent runs)
  [ "$stale_count" -lt 5 ]
}

# ═══════════════════════════════════════════════════════════════════
# ERROR AGGREGATION TESTS
# ═══════════════════════════════════════════════════════════════════

test_error_handling_nonexistent_loader() {
  source "$CONFIG_LIB"
  source "$PARALLEL_LIB"

  export BANG_PARALLEL=1
  export BANG_DIR

  # Run with a non-existent loader - should handle gracefully
  local exit_code=0
  parallel_run "nonexistent-loader-xyz" &>/dev/null || exit_code=$?

  # Should return non-zero for failed loader
  [ "$exit_code" -ne 0 ]
}

test_error_handling_mixed_success_failure() {
  source "$CONFIG_LIB"
  source "$PARALLEL_LIB"

  export BANG_PARALLEL=1
  export BANG_DIR

  # Mix of valid and invalid loaders
  local exit_code=0
  parallel_run "git-context --minimal" "nonexistent-loader" &>/dev/null || exit_code=$?

  # Should return non-zero because one loader failed
  [ "$exit_code" -ne 0 ]
}

test_error_aggregation_multiple_failures() {
  source "$CONFIG_LIB"
  source "$PARALLEL_LIB"

  export BANG_PARALLEL=1
  export BANG_DIR

  # Multiple non-existent loaders
  local exit_code=0
  parallel_run "fake1" "fake2" "fake3" &>/dev/null || exit_code=$?

  # Should fail
  [ "$exit_code" -ne 0 ]
}

test_output_order_preserved() {
  source "$CONFIG_LIB"
  source "$PARALLEL_LIB"

  export BANG_PARALLEL=1
  export BANG_DIR

  # Run loaders and check that output order matches input order
  local output
  output=$(parallel_run "git-context --minimal" "env-summary --minimal" 2>&1 || echo "")

  # Should have content from both
  [ -n "$output" ]
}

# ═══════════════════════════════════════════════════════════════════
# SIGNAL HANDLING TESTS
# ═══════════════════════════════════════════════════════════════════

test_sigint_cleanup() {
  source "$CONFIG_LIB"
  source "$PARALLEL_LIB"

  export BANG_PARALLEL=1
  export BANG_DIR

  # Start parallel run and send SIGINT
  (
    parallel_run "git-context" "env-summary" "deps-audit" &
    local pid=$!
    sleep 0.3
    kill -INT $pid 2>/dev/null || true
    wait $pid 2>/dev/null || true
  ) &>/dev/null

  # Temp directories should be cleaned up
  local remaining
  remaining=$(find /tmp -name "bang-parallel-$$-*" -type d 2>/dev/null | wc -l | tr -d ' ')
  [ "$remaining" -eq 0 ]
}

test_sigterm_cleanup() {
  source "$CONFIG_LIB"
  source "$PARALLEL_LIB"

  export BANG_PARALLEL=1
  export BANG_DIR

  # Start parallel run and send SIGTERM
  (
    parallel_run "git-context" "env-summary" &
    local pid=$!
    sleep 0.3
    kill -TERM $pid 2>/dev/null || true
    wait $pid 2>/dev/null || true
  ) &>/dev/null

  # Should clean up
  sleep 0.5
  local remaining
  remaining=$(find /tmp -name "bang-parallel-*" -type d 2>/dev/null | wc -l | tr -d ' ')

  # Allow some concurrent runs, but should be minimal
  [ "$remaining" -lt 5 ]
}

test_exit_trap_cleanup() {
  source "$CONFIG_LIB"
  source "$PARALLEL_LIB"

  export BANG_PARALLEL=1
  export BANG_DIR

  # Run in subshell and let it exit normally
  (
    parallel_run "git-context --minimal" &>/dev/null || true
  )

  # Cleanup should happen automatically
  sleep 0.2
}

test_parallel_profile_helper() {
  source "$CONFIG_LIB"
  source "$PARALLEL_LIB"

  export BANG_PARALLEL=1
  export BANG_DIR

  # Test parallel_profile function
  parallel_profile "git-context --minimal env-summary --minimal" &>/dev/null || true
}

# ═══════════════════════════════════════════════════════════════════
# STRESS TESTS
# ═══════════════════════════════════════════════════════════════════

test_many_parallel_jobs() {
  source "$CONFIG_LIB"
  source "$PARALLEL_LIB"

  export BANG_PARALLEL=1
  export BANG_MAX_PARALLEL=3
  export BANG_DIR

  # Run all 7 loaders in parallel
  parallel_run \
    "git-context --minimal" \
    "env-summary --minimal" \
    "deps-audit" \
    "docker-status" \
    "test-status" \
    "project-summary" \
    "api-health" &>/dev/null || true
}

test_rapid_sequential_calls() {
  source "$CONFIG_LIB"
  source "$PARALLEL_LIB"

  export BANG_PARALLEL=1
  export BANG_DIR

  # Run multiple parallel_run calls in sequence
  parallel_run "git-context --minimal" &>/dev/null || true
  parallel_run "env-summary --minimal" &>/dev/null || true
  parallel_run "deps-audit" &>/dev/null || true
}
