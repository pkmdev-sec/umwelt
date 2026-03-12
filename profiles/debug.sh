#!/usr/bin/env bash
# ============================================================================
# debug.sh — Debugging profile
# ============================================================================
# Purpose: Comprehensive debugging context including full environment details,
#          Docker logs, API health, recent error logs, and process info.
#          Designed for troubleshooting production issues.
#
# Usage: umwelt profile debug
#
# Dependencies: bash 3.2+, env-summary, git-context, docker-status,
#               api-health loaders, grep for log parsing, ps for processes
#
# Output: Full env vars, git state, Docker logs, API health, recent errors
#         from npm-debug.log and *.log files, system log excerpts (macOS),
#         and top 5 CPU/memory processes.
# ============================================================================
set -euo pipefail

UMWELT_DIR="${UMWELT_DIR:-$HOME/.claude/umwelt}"

echo "╔══════════════════════════════════════╗"
echo "║     BANG PROFILE: DEBUG              ║"
echo "╚══════════════════════════════════════╝"
echo ""

# Full environment
"$UMWELT_DIR/loaders/env-summary.sh" "--full"
echo ""

# Git state
"$UMWELT_DIR/loaders/git-context.sh" "--minimal"
echo ""

# Docker with logs
"$UMWELT_DIR/loaders/docker-status.sh" "--full"
echo ""

# API health
"$UMWELT_DIR/loaders/api-health.sh" "--full"
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
