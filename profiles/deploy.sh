#!/usr/bin/env bash
# umwelt profile: deploy
# Pre-deployment checklist — git clean, tests, deps, docker, APIs
# Usage: umwelt profile deploy
set -euo pipefail

UMWELT_DIR="${UMWELT_DIR:-$HOME/.claude/umwelt}"

echo "╔══════════════════════════════════════╗"
echo "║     BANG PROFILE: DEPLOY CHECK       ║"
echo "╚══════════════════════════════════════╝"
echo ""

# Deployment readiness checklist
echo "=== DEPLOY READINESS ==="
READY=true

# 1. Git clean?
if git rev-parse --is-inside-work-tree &>/dev/null; then
  DIRTY=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  if [ "$DIRTY" -gt 0 ]; then
    echo "✗ DIRTY WORKING TREE — ${DIRTY} uncommitted changes"
    READY=false
  else
    echo "✓ working tree clean"
  fi

  # On expected branch?
  BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
  echo "  branch: ${BRANCH}"

  # Pushed?
  LOCAL=$(git rev-parse HEAD 2>/dev/null)
  REMOTE=$(git rev-parse '@{upstream}' 2>/dev/null || echo "none")
  if [ "$REMOTE" = "none" ]; then
    echo "✗ NO UPSTREAM — branch not pushed"
    READY=false
  elif [ "$LOCAL" != "$REMOTE" ]; then
    AHEAD=$(git rev-list --count '@{upstream}..HEAD' 2>/dev/null || echo "?")
    echo "✗ UNPUSHED COMMITS — ${AHEAD} ahead of remote"
    READY=false
  else
    echo "✓ in sync with remote"
  fi
else
  echo "✗ NOT A GIT REPO"
  READY=false
fi

# 2. Dependencies
echo ""
"$UMWELT_DIR/loaders/deps-audit.sh"

# 3. Docker
echo ""
"$UMWELT_DIR/loaders/docker-status.sh" "--minimal"

# 4. APIs
echo ""
"$UMWELT_DIR/loaders/api-health.sh"

# 5. Build check
echo ""
echo "=== BUILD CHECK ==="
if [ -f "package.json" ]; then
  if command -v jq &>/dev/null; then
    HAS_BUILD=$(jq -r 'if .scripts.build then "True" else "False" end' package.json 2>/dev/null || echo "False")
  else
    HAS_BUILD=$(python3 -c "import json; d=json.load(open('package.json')); print('build' in d.get('scripts',{}))" 2>/dev/null || echo "False")
  fi
  if [ "$HAS_BUILD" = "True" ]; then
    echo "  build script: available (npm run build)"
    if [ -d "dist" ] || [ -d "build" ] || [ -d ".next" ]; then
      BUILD_DIR=$(ls -d dist build .next 2>/dev/null | head -1)
      BUILD_AGE=$(( ($(date +%s) - $(stat -f '%m' "$BUILD_DIR" 2>/dev/null || stat -c '%Y' "$BUILD_DIR" 2>/dev/null || echo 0)) / 60 ))
      echo "  last build: ${BUILD_DIR}/ (${BUILD_AGE} min ago)"
    else
      echo "  ✗ NO BUILD OUTPUT — run build first"
      READY=false
    fi
  fi
elif [ -f "Cargo.toml" ]; then
  if [ -d "target/release" ]; then
    echo "  ✓ release build exists"
  else
    echo "  ✗ no release build — run cargo build --release"
    READY=false
  fi
fi
echo "=== END BUILD CHECK ==="

# Verdict
echo ""
echo "════════════════════════════════"
if $READY; then
  echo "  VERDICT: ✓ READY TO DEPLOY"
else
  echo "  VERDICT: ✗ NOT READY — fix issues above"
fi
echo "════════════════════════════════"
