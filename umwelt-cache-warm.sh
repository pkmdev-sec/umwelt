#!/usr/bin/env bash
# bang-framework: Cache warming — runs on SessionStart
# Pre-computes all loaders and stores results in cache for <100ms subsequent reads.
# Usage: bang-cache-warm.sh
set -euo pipefail

BANG_DIR="${BANG_DIR:-$HOME/.claude/bang-framework}"

# Source config (loads cache system)
if [ -f "$BANG_DIR/lib/config.sh" ]; then
  source "$BANG_DIR/lib/config.sh"
fi

# Ensure cache dir exists
mkdir -p "${BANG_CACHE_DIR:-$HOME/.claude/.bang-cache}"

# Run all loaders in sequence, caching each result
# We run these with --minimal for speed (SessionStart should be <5s)
LOADERS=("git-context" "project-summary" "env-summary" "test-status")

for loader in "${LOADERS[@]}"; do
  LOADER_PATH="$BANG_DIR/loaders/${loader}.sh"
  if [ -f "$LOADER_PATH" ]; then
    KEY=$(cache_key "$loader" "--minimal")
    RESULT=$("$LOADER_PATH" --minimal 2>/dev/null || echo "[${loader}] unavailable")
    cache_set "$KEY" "$RESULT"
  fi
done

# Also warm the git-context delta timestamp
TS_FILE="${BANG_CACHE_DIR:-$HOME/.claude/.bang-cache}/git-context-last-call"
date +%s > "$TS_FILE"

echo "[bang] Cache warmed: ${#LOADERS[@]} loaders cached"
