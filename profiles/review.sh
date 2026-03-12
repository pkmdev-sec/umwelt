#!/usr/bin/env bash
# bang-framework profile: review
# Code review context — git diff, branch comparison, test status
# Usage: bang profile review [base-branch]
set -euo pipefail

BANG_DIR="${BANG_DIR:-$HOME/.claude/bang-framework}"
BASE_BRANCH="${1:-main}"

echo "╔══════════════════════════════════════╗"
echo "║     BANG PROFILE: CODE REVIEW        ║"
echo "╚══════════════════════════════════════╝"
echo ""

# Git state with diff
"$BANG_DIR/loaders/git-context.sh" "--diff"
echo ""

# Branch comparison
if git rev-parse --is-inside-work-tree &>/dev/null; then
  CURRENT=$(git branch --show-current 2>/dev/null || echo "HEAD")

  echo "=== BRANCH COMPARISON ==="
  echo "comparing: ${CURRENT} ← ${BASE_BRANCH}"

  # Commits since branch point
  COMMIT_COUNT=$(git rev-list --count "${BASE_BRANCH}..HEAD" 2>/dev/null || echo "?")
  echo "commits ahead: ${COMMIT_COUNT}"

  if [ "$COMMIT_COUNT" != "?" ] && [ "$COMMIT_COUNT" -gt 0 ]; then
    echo ""
    echo "--- commits ---"
    git log --oneline "${BASE_BRANCH}..HEAD" 2>/dev/null | head -20

    echo ""
    echo "--- files changed ---"
    git diff --stat "${BASE_BRANCH}...HEAD" 2>/dev/null | tail -20

    echo ""
    echo "--- diffstat ---"
    INSERTIONS=$(git diff "${BASE_BRANCH}...HEAD" --shortstat 2>/dev/null)
    echo "$INSERTIONS"
  fi
  echo "=== END BRANCH COMPARISON ==="
fi

echo ""
"$BANG_DIR/loaders/test-status.sh" "--last"
