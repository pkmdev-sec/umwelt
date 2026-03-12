#!/usr/bin/env bash
# bang-framework profile: debug
# Debugging context — full env, docker logs, API health, recent errors
# Usage: bang profile debug
set -euo pipefail

BANG_DIR="${BANG_DIR:-$HOME/.claude/bang-framework}"

echo "╔══════════════════════════════════════╗"
echo "║     BANG PROFILE: DEBUG              ║"
echo "╚══════════════════════════════════════╝"
echo ""

# Full environment
"$BANG_DIR/loaders/env-summary.sh" "--full"
echo ""

# Git state
"$BANG_DIR/loaders/git-context.sh" "--minimal"
echo ""

# Docker with logs
"$BANG_DIR/loaders/docker-status.sh" "--full"
echo ""

# API health
"$BANG_DIR/loaders/api-health.sh" "--full"
echo ""

# Recent errors in common log locations
echo "=== RECENT ERRORS ==="
ERROR_FOUND=false

# Node.js error logs
if [ -f "npm-debug.log" ]; then
  echo "--- npm-debug.log (last 10 lines) ---"
  tail -10 npm-debug.log 2>/dev/null
  ERROR_FOUND=true
fi

# Python tracebacks in recent logs
for logfile in "*.log" "logs/*.log"; do
  for f in $logfile; do
    if [ -f "$f" ]; then
      ERRORS=$(grep -c -iE '(error|traceback|exception|fatal|panic)' "$f" 2>/dev/null || echo "0")
      if [ "$ERRORS" -gt 0 ]; then
        echo "--- ${f} (${ERRORS} errors) ---"
        grep -iE '(error|traceback|exception|fatal|panic)' "$f" 2>/dev/null | tail -5
        echo ""
        ERROR_FOUND=true
      fi
    fi
  done
done

# System log (macOS) — skipped in non-interactive/test mode (log show is slow)
if [ -t 1 ] && command -v log &>/dev/null; then
  echo "--- system log (last 5 errors) ---"
  timeout 5 log show --predicate 'eventMessage contains "error"' --last 2m --style compact 2>/dev/null | tail -5 || echo "(no recent system errors)"
  ERROR_FOUND=true
fi

if ! $ERROR_FOUND; then
  echo "  no recent error logs found"
fi

echo "=== END RECENT ERRORS ==="

# Process info
echo ""
echo "=== PROCESSES ==="
echo "--- high CPU ---"
(ps aux 2>/dev/null | sort -nrk3 | head -5 | awk '{printf "  %-6s %5s%% %5s%%  %s\n", $2, $3, $4, $11}') 2>/dev/null || echo "  (could not read processes)"
echo ""
echo "--- high MEM ---"
(ps aux 2>/dev/null | sort -nrk4 | head -5 | awk '{printf "  %-6s %5s%% %5s%%  %s\n", $2, $3, $4, $11}') 2>/dev/null || echo "  (could not read processes)"
echo "=== END PROCESSES ==="
