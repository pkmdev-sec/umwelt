#!/usr/bin/env bash
# ============================================================================
# dev.sh — Development profile
# ============================================================================
# Purpose: Full development context profile combining git state, test status,
#          environment summary, and project overview. Optimized for active
#          development sessions with parallel loader execution.
#
# Usage: umwelt profile dev [--full|--minimal]
#        Minimal mode runs git-context + project-summary only (fast).
#
# Dependencies: bash 3.2+, parallel.sh, git-context, test-status,
#               env-summary, project-summary loaders
#
# Output: Parallel execution of 4 loaders (git-context, test-status,
#         env-summary, project-summary) with combined formatted output.
# ============================================================================
set -euo pipefail

UMWELT_DIR="${UMWELT_DIR:-$HOME/.claude/umwelt}"
MODE="${1:-default}"

# Source config and parallel execution
if [ -f "$UMWELT_DIR/lib/config.sh" ]; then
  source "$UMWELT_DIR/lib/config.sh"
fi
if [ -f "$UMWELT_DIR/lib/parallel.sh" ]; then
  source "$UMWELT_DIR/lib/parallel.sh"
fi

# Minimal mode: git + project summary only (fast, for SubagentStart)
if [ "$MODE" = "--minimal" ]; then
  echo "── umwelt: dev (minimal) ──"
  parallel_run \
    "git-context --minimal" \
    "project-summary --minimal"
  exit 0
fi

echo "╔══════════════════════════════════════╗"
echo "║     BANG PROFILE: DEVELOPMENT        ║"
echo "╚══════════════════════════════════════╝"
echo ""

# Run all 4 loaders in parallel (no dependencies between them)
parallel_run \
  "git-context $MODE" \
  "test-status --last" \
  "env-summary --minimal" \
  "project-summary $MODE"
