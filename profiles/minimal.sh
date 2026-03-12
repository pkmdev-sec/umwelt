#!/usr/bin/env bash
# bang-framework profile: minimal
# Ultra-lightweight context — cwd + git branch only
# Target: <200 tokens per injection
# Designed for haiku-class models where every token counts
# Usage: bang profile minimal
set -euo pipefail

BANG_DIR="${BANG_DIR:-$HOME/.claude/bang-framework}"

echo "── bang: minimal ──"

# CWD
echo "cwd: $(pwd)"

# Git branch (if in a repo)
if git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
    branch=$(git branch --show-current 2>/dev/null || echo "detached")
    echo "branch: ${branch}"
fi

echo "── end ──"
