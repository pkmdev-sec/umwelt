#!/usr/bin/env bash
# ============================================================================
# minimal.sh — Minimal profile
# ============================================================================
# Purpose: Ultra-lightweight context injection with only essential info:
#          current working directory and git branch. Target: <200 tokens.
#          Designed for Haiku-class models or high-budget situations.
#
# Usage: umwelt profile minimal
#
# Dependencies: bash 3.2+, git (optional)
#
# Output: Current working directory path and git branch (if in a git repo).
#         Extremely fast, no loader dependencies, minimal token footprint.
# ============================================================================
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
