#!/usr/bin/env bash
# ============================================================================
# custom-loader.sh — Example: How to create a custom Umwelt loader
# ============================================================================
# This example demonstrates how to write a custom loader that integrates
# with the Umwelt context injection system.
#
# Loaders are shell scripts that output context information as structured text.
# They are called by Umwelt and their output is injected into Claude Code's
# system prompt to provide environmental awareness.
#
# To install: Copy to ~/.claude/umwelt/loaders/ and it will be auto-discovered.
# ============================================================================
set -euo pipefail

# Every loader should start with a section header
echo "## Custom Project Metrics"
echo ""

# Example: Gather custom metrics from your project
# Loaders should be fast (< 2 seconds) and output concise text

# 1. Check for recent TODOs
TODO_COUNT=$(grep -r "TODO" --include="*.{js,ts,py,rs}" . 2>/dev/null | wc -l | tr -d ' ')
echo "Open TODOs: ${TODO_COUNT}"

# 2. Check code coverage if available
if [ -f "coverage/coverage-summary.json" ]; then
    # Use jq if available, fallback to grep
    if command -v jq &>/dev/null; then
        COVERAGE=$(jq -r '.total.lines.pct' coverage/coverage-summary.json 2>/dev/null)
        echo "Line Coverage: ${COVERAGE}%"
    fi
fi

# 3. Check for security advisories
if [ -f "package-lock.json" ]; then
    AUDIT_ISSUES=$(npm audit --json 2>/dev/null | jq '.metadata.vulnerabilities.total // 0' 2>/dev/null)
    if [ -n "$AUDIT_ISSUES" ] && [ "$AUDIT_ISSUES" != "0" ]; then
        echo "Security Issues: ${AUDIT_ISSUES} (run 'npm audit' for details)"
    else
        echo "Security: No known vulnerabilities"
    fi
fi

# 4. Custom team conventions
echo ""
echo "### Team Conventions"
if [ -f ".editorconfig" ]; then
    echo "- EditorConfig: active"
fi
if [ -f ".prettierrc" ] || [ -f ".prettierrc.json" ]; then
    echo "- Prettier: configured"
fi
if [ -f ".eslintrc.json" ] || [ -f ".eslintrc.js" ]; then
    echo "- ESLint: configured"
fi

# Loaders should exit cleanly
exit 0
