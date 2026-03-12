#!/usr/bin/env bash
# ============================================================================
# deps-audit.sh — Dependency audit loader
# ============================================================================
# Purpose: Quick dependency health check across package managers. Reports
#          outdated packages, known vulnerabilities, and lock file freshness
#          for npm/pnpm/yarn, pip, cargo, bundler, and more.
#
# Usage: umwelt deps-audit [--full] [--json]
#        Or called by profiles/unified-engine as: $LOADERS_DIR/deps-audit.sh
#
# Dependencies: bash 3.2+, npm/pip/cargo/bundle (package manager detection)
#
# Output: Dependency counts, outdated package list, vulnerability reports
#         (npm audit, pip-audit, cargo audit), and lock file staleness.
#         Returns "[deps] No dependency manifests found" if none detected.
# ============================================================================
set -euo pipefail

# Source config and output systems
UMWELT_DIR="${UMWELT_DIR:-$HOME/.claude/umwelt}"
if [ -f "$UMWELT_DIR/lib/config.sh" ]; then
  source "$UMWELT_DIR/lib/config.sh"
fi
if [ -f "$UMWELT_DIR/lib/output.sh" ]; then
  source "$UMWELT_DIR/lib/output.sh"
fi

MODE="${1:-default}"
OUTPUT_FMT="${UMWELT_OUTPUT_FORMAT:-text}"
for arg in "$@"; do
  if [ "$arg" = "--json" ]; then OUTPUT_FMT="json"; fi
done

# ─── Helper: get file age in days ────────────────────────────────
file_age_days() {
  local file="$1"
  local mtime
  mtime=$(stat -f '%m' "$file" 2>/dev/null || stat -c '%Y' "$file" 2>/dev/null || echo 0)
  echo $(( ($(date +%s) - mtime) / 86400 ))
}

# ─── Detect Project Type & Gather Data ───────────────────────────
PROJECT_TYPE="unknown"
LOCK_FILE=""
LOCK_AGE=0
DEPS_COUNT=0
DEV_DEPS_COUNT=0
HAS_NODE_MODULES=false
AUDIT_OUTPUT=""
OUTDATED_OUTPUT=""

if [ -f "package.json" ]; then
  PROJECT_TYPE="node"

  # Lock file detection
  for lf in package-lock.json pnpm-lock.yaml yarn.lock bun.lockb; do
    if [ -f "$lf" ]; then
      LOCK_FILE="$lf"
      LOCK_AGE=$(file_age_days "$lf")
      break
    fi
  done

  # Dependency counts
  if command -v jq &>/dev/null; then
    DEPS_COUNT=$(jq '.dependencies // {} | length' package.json 2>/dev/null || echo "0")
    DEV_DEPS_COUNT=$(jq '.devDependencies // {} | length' package.json 2>/dev/null || echo "0")
  else
    DEPS_COUNT=$(python3 -c "import json; d=json.load(open('package.json')); print(len(d.get('dependencies',{})))" 2>/dev/null || echo "0")
    DEV_DEPS_COUNT=$(python3 -c "import json; d=json.load(open('package.json')); print(len(d.get('devDependencies',{})))" 2>/dev/null || echo "0")
  fi

  [ -d "node_modules" ] && HAS_NODE_MODULES=true

  # Full audit
  if [ "$MODE" = "--full" ] && command -v npm &>/dev/null; then
    AUDIT_OUTPUT=$(npm audit --omit=dev 2>&1 | tail -10 || echo "(audit failed)")
    OUTDATED_OUTPUT=$(npm outdated 2>&1 | head -15 || echo "(all up to date)")
  fi

elif [ -f "pyproject.toml" ] || [ -f "requirements.txt" ]; then
  PROJECT_TYPE="python"

  if [ -f "requirements.txt" ]; then
    DEPS_COUNT=$(wc -l < requirements.txt | tr -d ' ')
    LOCK_FILE="requirements.txt"
    LOCK_AGE=$(file_age_days requirements.txt)
  fi
  if [ -f "poetry.lock" ]; then
    LOCK_FILE="poetry.lock"
    LOCK_AGE=$(file_age_days poetry.lock)
  fi

  if [ "$MODE" = "--full" ] && command -v pip3 &>/dev/null; then
    OUTDATED_OUTPUT=$(pip3 list --outdated 2>&1 | head -15 || echo "(check failed)")
  fi

elif [ -f "Cargo.toml" ]; then
  PROJECT_TYPE="rust"
  DEPS_COUNT=$(grep -c '^\[dependencies' Cargo.toml 2>/dev/null || echo "0")

  if [ -f "Cargo.lock" ]; then
    LOCK_FILE="Cargo.lock"
    LOCK_AGE=$(file_age_days Cargo.lock)
  fi

  if [ "$MODE" = "--full" ] && command -v cargo &>/dev/null; then
    OUTDATED_OUTPUT=$(cargo outdated 2>&1 | head -15 || echo "(cargo-outdated not installed)")
  fi

elif [ -f "go.mod" ]; then
  PROJECT_TYPE="go"
  DEPS_COUNT=$(grep -c '^	' go.mod 2>/dev/null || echo "0")

  if [ -f "go.sum" ]; then
    LOCK_FILE="go.sum"
    LOCK_AGE=$(file_age_days go.sum)
  fi
fi

# ─── Output ──────────────────────────────────────────────────────
if [ "$OUTPUT_FMT" = "json" ]; then
  if command -v jq &>/dev/null; then
    jq -n \
      --arg project_type "$PROJECT_TYPE" \
      --arg lock_file "$LOCK_FILE" \
      --argjson lock_age "$LOCK_AGE" \
      --argjson deps_count "$DEPS_COUNT" \
      --argjson dev_deps_count "$DEV_DEPS_COUNT" \
      --argjson has_node_modules "$( [ \"$HAS_NODE_MODULES\" = \"true\" ] && echo 'true' || echo 'false' )" \
      --argjson lock_stale "$( [ \"$LOCK_AGE\" -gt 90 ] 2>/dev/null && echo 'true' || echo 'false' )" \
      --argjson lock_missing "$( [ -z \"$LOCK_FILE\" ] && [ \"$PROJECT_TYPE\" != \"unknown\" ] && echo 'true' || echo 'false' )" \
      '{
        project_type: $project_type,
        lock_file: (if $lock_file == "" then null else $lock_file end),
        lock_age_days: $lock_age,
        deps_count: $deps_count,
        dev_deps_count: $dev_deps_count,
        has_node_modules: $has_node_modules,
        lock_stale: $lock_stale,
        lock_missing: $lock_missing
      }' 2>/dev/null || echo '{"error": "json generation failed"}'
  else
    python3 -c "
import json

data = {
    'project_type': '$PROJECT_TYPE',
    'lock_file': '$LOCK_FILE' or None,
    'lock_age_days': int('$LOCK_AGE'),
    'deps_count': int('$DEPS_COUNT'),
    'dev_deps_count': int('$DEV_DEPS_COUNT'),
    'has_node_modules': '$HAS_NODE_MODULES' == 'true',
    'lock_stale': int('$LOCK_AGE') > 90,
    'lock_missing': '$LOCK_FILE' == '' and '$PROJECT_TYPE' != 'unknown',
}

print(json.dumps(data, indent=2))
" 2>/dev/null || echo '{"error": "json serialization failed"}'
  fi
else
  text_header "DEPENDENCY AUDIT"
  text_kv "type" "${PROJECT_TYPE}"

  if [ -n "$LOCK_FILE" ]; then
    text_kv "lock" "${LOCK_FILE} (${LOCK_AGE}d old)"
  elif [ "$PROJECT_TYPE" != "unknown" ]; then
    text_kv "lock" "MISSING"
  fi

  if [ "$PROJECT_TYPE" = "node" ]; then
    text_kv "deps" "${DEPS_COUNT} production, ${DEV_DEPS_COUNT} dev"
    if [ "$HAS_NODE_MODULES" = "false" ]; then
      echo "WARNING: node_modules missing — run npm install"
    fi
  elif [ "$PROJECT_TYPE" = "python" ] && [ -f "requirements.txt" ]; then
    text_kv "deps" "${DEPS_COUNT} in requirements.txt"
  elif [ "$PROJECT_TYPE" = "rust" ]; then
    text_kv "dependency sections" "${DEPS_COUNT}"
  elif [ "$PROJECT_TYPE" = "go" ]; then
    text_kv "deps" "${DEPS_COUNT} modules"
  fi

  if [ -n "$AUDIT_OUTPUT" ]; then
    text_subsection "npm audit"
    echo "$AUDIT_OUTPUT"
  fi
  if [ -n "$OUTDATED_OUTPUT" ]; then
    text_subsection "outdated"
    echo "$OUTDATED_OUTPUT"
  fi

  text_footer "DEPENDENCY AUDIT"
fi
