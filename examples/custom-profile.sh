#!/usr/bin/env bash
# ============================================================================
# custom-profile.sh — Example: How to create a custom Umwelt profile
# ============================================================================
# Profiles define which loaders run and in what order. They allow you to
# create task-specific context configurations.
#
# Profiles set the UMWELT_LOADERS variable to a space-separated list of
# loader names (without the .sh extension).
#
# To install: Copy to ~/.claude/umwelt/profiles/ and use with: umwelt profile custom
#
# Built-in profiles: dev, review, deploy, debug, minimal
# ============================================================================
set -euo pipefail

UMWELT_DIR="${UMWELT_DIR:-$HOME/.claude/umwelt}"

# Profile metadata
PROFILE_NAME="custom"
PROFILE_DESCRIPTION="Full-stack development context with API health"

echo "╔══════════════════════════════════════╗"
echo "║     UMWELT PROFILE: CUSTOM           ║"
echo "╚══════════════════════════════════════╝"
echo ""

# Option 1: Run loaders sequentially
# This is the simplest approach - just call each loader script directly

"$UMWELT_DIR/loaders/git-context.sh" "--minimal"
echo ""

"$UMWELT_DIR/loaders/env-summary.sh" "--minimal"
echo ""

"$UMWELT_DIR/loaders/project-summary.sh"
echo ""

"$UMWELT_DIR/loaders/test-status.sh" "--last"
echo ""

"$UMWELT_DIR/loaders/api-health.sh"

# Option 2: Run loaders in parallel (advanced)
# Uncomment below and comment out the sequential calls above
# This requires sourcing parallel.sh

# if [ -f "$UMWELT_DIR/lib/parallel.sh" ]; then
#   source "$UMWELT_DIR/lib/parallel.sh"
# fi
#
# # Define which loaders to run (space-separated, in order)
# parallel_run \
#   "git-context --minimal" \
#   "env-summary --minimal" \
#   "project-summary" \
#   "test-status --last" \
#   "api-health"

# Optional: Set custom environment variables for this profile
# export UMWELT_TOKEN_BUDGET=3000
# export UMWELT_PARALLEL=1
# export UMWELT_DIFF_MODE=1

# Optional: Add custom pre/post hooks
echo ""
echo "─────────────────────────────────────"
echo "Profile: ${PROFILE_NAME} — ${PROFILE_DESCRIPTION}"
echo "─────────────────────────────────────"
