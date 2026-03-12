#!/usr/bin/env bash
# umwelt profile: minimal
# Ultra-lightweight context — cwd + git branch only
# Target: <200 tokens per injection
# Designed for haiku-class models where every token counts
# Usage: umwelt profile minimal
set -euo pipefail

UMWELT_DIR="${UMWELT_DIR:-$HOME/.claude/umwelt}"

echo "── umwelt: minimal ──"

# CWD
echo "cwd: $(pwd)"

# Git branch (if in a repo)
if git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
    branch=$(git branch --show-current 2>/dev/null || echo "detached")
    echo "branch: ${branch}"
fi

echo "── end ──"
