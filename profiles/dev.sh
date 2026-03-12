#!/usr/bin/env bash
# umwelt profile: dev
# Full development context — git state, tests, environment, project overview
# Usage: umwelt profile dev [--full|--minimal]
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
