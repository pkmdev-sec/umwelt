#!/usr/bin/env bash
# bang-framework: Smart PreCompact (Innovation 3)
# When compaction is about to happen, collects critical environment state
# into a compact summary that survives the compaction cycle.
#
# Strategy:
#   1. Collect current critical state (git, task, modified files, test status)
#   2. Write structured JSON to .cache/precompact-state.json for post-compact re-injection
#   3. Output a compact human-readable summary for the compaction snapshot
#   4. Discard ephemeral data (processes, load averages, API health)
#
# On SessionStart after compaction: detect state file, re-inject context
# Usage: bang-precompact.sh
set -euo pipefail

BANG_DIR="${BANG_DIR:-$HOME/.claude/bang-framework}"
CACHE_DIR="${BANG_CACHE_DIR:-$HOME/.claude/.bang-cache}"
STATE_FILE="$CACHE_DIR/precompact-state.json"

# Source config
if [ -f "$BANG_DIR/lib/config.sh" ]; then
  source "$BANG_DIR/lib/config.sh"
fi
if [ -f "$BANG_DIR/lib/output.sh" ]; then
  source "$BANG_DIR/lib/output.sh"
fi

mkdir -p "$CACHE_DIR"

# ─── Collect Critical State ─────────────────────────────────────

# Git state
GIT_BRANCH=""
GIT_HEAD=""
GIT_REPO=""
GIT_STAGED=0
GIT_UNSTAGED=0
GIT_UNTRACKED=0
GIT_MODIFIED_FILES=""

if git rev-parse --is-inside-work-tree &>/dev/null; then
  GIT_BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
  GIT_HEAD=$(git rev-parse --short HEAD 2>/dev/null || echo "none")
  GIT_REPO=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "unknown")

  # Counts from porcelain
  GIT_STAGED=$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
  GIT_UNSTAGED=$(git diff --name-only 2>/dev/null | wc -l | tr -d ' ')
  GIT_UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')

  # Modified files list (staged + unstaged, limited to 20)
  GIT_MODIFIED_FILES=$(
    { git diff --cached --name-only 2>/dev/null; git diff --name-only 2>/dev/null; } \
    | sort -u | head -20 | tr '\n' ',' | sed 's/,$//'
  )
fi

# Test status (quick check — last result only, no re-run)
TEST_FRAMEWORK=""
TEST_LAST_RESULT=""
if [ -f "package.json" ]; then
  TEST_FRAMEWORK="node"
  # Check for common test result indicators
  if [ -d "coverage" ]; then TEST_LAST_RESULT="coverage-exists"; fi
elif [ -f "pytest.ini" ] || [ -f "setup.cfg" ] || [ -f "pyproject.toml" ]; then
  TEST_FRAMEWORK="python"
  if [ -d ".pytest_cache" ]; then TEST_LAST_RESULT="pytest-cache-exists"; fi
elif [ -f "Cargo.toml" ]; then
  TEST_FRAMEWORK="rust"
fi

# Current working directory & project type
CWD="$(pwd)"
PROJECT_TYPE=""
if [ -f "package.json" ]; then PROJECT_TYPE="node"
elif [ -f "Cargo.toml" ]; then PROJECT_TYPE="rust"
elif [ -f "pyproject.toml" ] || [ -f "setup.py" ]; then PROJECT_TYPE="python"
elif [ -f "go.mod" ]; then PROJECT_TYPE="go"
elif [ -f "Package.swift" ]; then PROJECT_TYPE="swift"
fi

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# ─── Write JSON State File ──────────────────────────────────────
# This file persists through compaction and can be re-loaded on SessionStart

if command -v jq &>/dev/null; then
  jq -n \
    --arg timestamp "$TIMESTAMP" \
    --arg cwd "$CWD" \
    --arg project_type "$PROJECT_TYPE" \
    --arg git_repo "$GIT_REPO" \
    --arg git_branch "$GIT_BRANCH" \
    --arg git_head "$GIT_HEAD" \
    --argjson git_staged "$GIT_STAGED" \
    --argjson git_unstaged "$GIT_UNSTAGED" \
    --argjson git_untracked "$GIT_UNTRACKED" \
    --arg git_modified_files "$GIT_MODIFIED_FILES" \
    --arg test_framework "$TEST_FRAMEWORK" \
    --arg test_last_result "$TEST_LAST_RESULT" \
    '{
      precompact_version: 2,
      timestamp: $timestamp,
      cwd: $cwd,
      project_type: (if $project_type == "" then null else $project_type end),
      git: {
        repo: (if $git_repo == "" then null else $git_repo end),
        branch: (if $git_branch == "" then null else $git_branch end),
        head: (if $git_head == "" then null else $git_head end),
        staged: $git_staged,
        unstaged: $git_unstaged,
        untracked: $git_untracked,
        modified_files: (if $git_modified_files == "" then [] else ($git_modified_files | split(",")) end)
      },
      test: {
        framework: (if $test_framework == "" then null else $test_framework end),
        last_result: (if $test_last_result == "" then null else $test_last_result end)
      }
    }' > "$STATE_FILE" 2>/dev/null
else
  python3 -c "
import json, sys

data = {
    'precompact_version': 2,
    'timestamp': '$TIMESTAMP',
    'cwd': '$CWD',
    'project_type': '$PROJECT_TYPE' or None,
    'git': {
        'repo': '$GIT_REPO' or None,
        'branch': '$GIT_BRANCH' or None,
        'head': '$GIT_HEAD' or None,
        'staged': int('$GIT_STAGED'),
        'unstaged': int('$GIT_UNSTAGED'),
        'untracked': int('$GIT_UNTRACKED'),
        'modified_files': [f for f in '$GIT_MODIFIED_FILES'.split(',') if f]
    },
    'test': {
        'framework': '$TEST_FRAMEWORK' or None,
        'last_result': '$TEST_LAST_RESULT' or None,
    }
}

with open('$STATE_FILE', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null
fi

# ─── Output Compact Summary (injected into compaction) ──────────
# This is the text Claude sees during compaction. Keep it minimal but
# information-dense so LLM retains project understanding.

echo "── bang: pre-compaction context snapshot ──"
echo ""
echo "cwd: $CWD"
if [ -n "$PROJECT_TYPE" ]; then
  echo "project: $PROJECT_TYPE"
fi

if [ -n "$GIT_BRANCH" ]; then
  echo "git: $GIT_REPO | branch: $GIT_BRANCH | head: $GIT_HEAD"
  echo "status: staged=$GIT_STAGED unstaged=$GIT_UNSTAGED untracked=$GIT_UNTRACKED"
  if [ -n "$GIT_MODIFIED_FILES" ]; then
    echo "modified: $GIT_MODIFIED_FILES"
  fi
fi

if [ -n "$TEST_FRAMEWORK" ]; then
  echo "tests: $TEST_FRAMEWORK${TEST_LAST_RESULT:+ ($TEST_LAST_RESULT)}"
fi

echo ""
echo "state-file: $STATE_FILE"
echo "── end pre-compaction snapshot ──"

# ─── Re-inject from state file (called on SessionStart) ─────────
# This function is meant to be sourced and called, not run directly.
# Usage: source bang-precompact.sh && reinject_precompact_state
reinject_precompact_state() {
  if [ ! -f "$STATE_FILE" ]; then
    return 0
  fi

  echo "── bang: restoring pre-compaction state ──"
  echo ""

  if command -v jq &>/dev/null; then
    local branch repo head staged unstaged untracked modified cwd ptype
    cwd=$(jq -r '.cwd // ""' "$STATE_FILE" 2>/dev/null)
    ptype=$(jq -r '.project_type // ""' "$STATE_FILE" 2>/dev/null)
    repo=$(jq -r '.git.repo // ""' "$STATE_FILE" 2>/dev/null)
    branch=$(jq -r '.git.branch // ""' "$STATE_FILE" 2>/dev/null)
    head=$(jq -r '.git.head // ""' "$STATE_FILE" 2>/dev/null)
    staged=$(jq -r '.git.staged // 0' "$STATE_FILE" 2>/dev/null)
    unstaged=$(jq -r '.git.unstaged // 0' "$STATE_FILE" 2>/dev/null)
    untracked=$(jq -r '.git.untracked // 0' "$STATE_FILE" 2>/dev/null)
    modified=$(jq -r '.git.modified_files | join(",")' "$STATE_FILE" 2>/dev/null)

    echo "restored-cwd: $cwd"
    [ -n "$ptype" ] && [ "$ptype" != "null" ] && echo "restored-project: $ptype"
    if [ -n "$branch" ] && [ "$branch" != "null" ]; then
      echo "restored-git: $repo | branch: $branch | head: $head"
      echo "restored-status: staged=$staged unstaged=$unstaged untracked=$untracked"
      [ -n "$modified" ] && echo "restored-modified: $modified"
    fi
  else
    python3 -c "
import json
with open('$STATE_FILE') as f:
    d = json.load(f)
print(f\"restored-cwd: {d['cwd']}\")
if d.get('project_type'):
    print(f\"restored-project: {d['project_type']}\")
g = d.get('git', {})
if g.get('branch'):
    print(f\"restored-git: {g['repo']} | branch: {g['branch']} | head: {g['head']}\")
    print(f\"restored-status: staged={g['staged']} unstaged={g['unstaged']} untracked={g['untracked']}\")
    mf = ','.join(g.get('modified_files', []))
    if mf:
        print(f\"restored-modified: {mf}\")
" 2>/dev/null
  fi

  echo ""
  echo "── end restored state ──"

  # Clean up state file after re-injection
  rm -f "$STATE_FILE"
}
