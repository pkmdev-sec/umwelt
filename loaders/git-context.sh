#!/usr/bin/env bash
# umwelt: git-context loader
# Outputs current git state — branch, status, recent commits, stash
# Usage: umwelt git-context [--full|--minimal|--diff] [--json]
set -euo pipefail

# Source config, cache, and output systems
UMWELT_DIR="${UMWELT_DIR:-$HOME/.claude/umwelt}"
if [ -f "$UMWELT_DIR/lib/config.sh" ]; then
  source "$UMWELT_DIR/lib/config.sh"
fi
if [ -f "$UMWELT_DIR/lib/output.sh" ]; then
  source "$UMWELT_DIR/lib/output.sh"
fi

MODE="${1:-default}"
# Check for --json flag in any position
OUTPUT_FMT="${UMWELT_OUTPUT_FORMAT:-text}"
for arg in "$@"; do
  if [ "$arg" = "--json" ]; then OUTPUT_FMT="json"; fi
done

# Bail early if not in a git repo
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  if [ "$OUTPUT_FMT" = "json" ]; then
    echo '{"error": "not a git repository", "is_repo": false}'
  else
    echo "[git] Not a git repository"
  fi
  exit 0
fi

# ─── Delta Mode (only changes since last call) ────────────────
if [ "$MODE" = "--delta" ]; then
  CACHE_TS_FILE="${UMWELT_CACHE_DIR:-$HOME/.claude/.bang-cache}/git-context-last-call"
  mkdir -p "$(dirname "$CACHE_TS_FILE")"
  NOW=$(date +%s)

  if [ -f "$CACHE_TS_FILE" ]; then
    LAST_TS=$(cat "$CACHE_TS_FILE")
    SECONDS_AGO=$((NOW - LAST_TS))

    # Files modified since last call (working tree)
    CHANGED=$(git diff --name-status 2>/dev/null || true)
    STAGED=$(git diff --cached --name-status 2>/dev/null || true)

    if [ -z "$CHANGED" ] && [ -z "$STAGED" ]; then
      echo "[git-delta] No changes since last check (${SECONDS_AGO}s ago)"
    else
      echo "[git-delta] Changes since last check (${SECONDS_AGO}s ago):"
      if [ -n "$STAGED" ]; then
        echo "  staged:"
        echo "$STAGED" | head -10 | sed 's/^/    /'
      fi
      if [ -n "$CHANGED" ]; then
        echo "  unstaged:"
        echo "$CHANGED" | head -10 | sed 's/^/    /'
      fi
      # Abbreviated diff (max 30 lines)
      DELTA_DIFF=$(git diff --stat 2>/dev/null | tail -5)
      if [ -n "$DELTA_DIFF" ]; then
        echo "  diff summary:"
        echo "$DELTA_DIFF" | sed 's/^/    /'
      fi
    fi
  else
    # First call — show summary only
    BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
    echo "[git-delta] First snapshot: branch=$BRANCH"
    git status --short 2>/dev/null | head -10 | sed 's/^/  /'
  fi

  # Update timestamp
  echo "$NOW" > "$CACHE_TS_FILE"
  exit 0
fi

# ─── Normalized Git Status (bash 3.2 compatible) ────────────────
# Extracted to a function because bash 3.2 cannot parse '||' with
# a piped while-loop inside process substitution (< <(...)).
_git_status_normalized() {
  local v2_output
  v2_output=$(git status --porcelain=v2 2>/dev/null) && { echo "$v2_output"; return 0; }
  # Fallback: parse porcelain v1 into v2-compatible format
  git status --porcelain 2>/dev/null | while IFS= read -r pline; do
    case "$pline" in
      "?? "*) echo "? ${pline:3}" ;;
      "UU "*|"AA "*|"DD "*) echo "u ${pline:3}" ;;
      *)
        x=${pline:0:1}
        y=${pline:1:1}
        if [ "$x" != " " ] && [ "$x" != "?" ]; then echo "1 ${x}${y} staged"; fi
        ;;
    esac
  done
}

# ─── Gather Data Using Porcelain Commands ───────────────────────
# Use git status --porcelain=v2 for reliable machine-parseable output
BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
REPO=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "unknown")
HEAD_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "none")

# Upstream tracking
UPSTREAM=$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || echo "")
AHEAD=0
BEHIND=0
if [ -n "$UPSTREAM" ]; then
  AHEAD=$(git rev-list --count '@{upstream}..HEAD' 2>/dev/null || echo "0")
  BEHIND=$(git rev-list --count 'HEAD..@{upstream}' 2>/dev/null || echo "0")
fi

# Parse porcelain status for accurate counts
STAGED_COUNT=0
UNSTAGED_COUNT=0
UNTRACKED_COUNT=0
CONFLICT_COUNT=0

while IFS= read -r line; do
  case "$line" in
    "1 "*)
      # Ordinary changed entry: "1 XY ..."
      local_xy=$(echo "$line" | cut -d' ' -f2)
      x=${local_xy:0:1}
      y=${local_xy:1:1}
      if [ "$x" != "." ]; then STAGED_COUNT=$((STAGED_COUNT + 1)); fi
      if [ "$y" != "." ]; then UNSTAGED_COUNT=$((UNSTAGED_COUNT + 1)); fi
      ;;
    "2 "*)
      # Renamed/copied entry
      local_xy=$(echo "$line" | cut -d' ' -f2)
      x=${local_xy:0:1}
      y=${local_xy:1:1}
      if [ "$x" != "." ]; then STAGED_COUNT=$((STAGED_COUNT + 1)); fi
      if [ "$y" != "." ]; then UNSTAGED_COUNT=$((UNSTAGED_COUNT + 1)); fi
      ;;
    "u "*)
      # Unmerged entry (conflict)
      CONFLICT_COUNT=$((CONFLICT_COUNT + 1))
      ;;
    "? "*)
      # Untracked
      UNTRACKED_COUNT=$((UNTRACKED_COUNT + 1))
      ;;
  esac
done < <(_git_status_normalized)

# Recent commits (configurable count)
LOG_COUNT="${UMWELT_GIT_LOG_COUNT:-5}"
RECENT_COMMITS=""
RECENT_COMMITS_JSON=""
if git log --oneline -1 &>/dev/null; then
  RECENT_COMMITS=$(git log --oneline -"$LOG_COUNT" 2>/dev/null || echo "")

  # Build JSON array of recent commits using jq or python3 fallback
  if command -v jq &>/dev/null; then
    RECENT_COMMITS_JSON=$(git log --format='{"sha": "%h", "message": "%s", "author": "%an", "date": "%ci"}' -"$LOG_COUNT" 2>/dev/null | jq -s '.' 2>/dev/null || echo "[]")
  else
    RECENT_COMMITS_JSON=$(git log --format='{"sha": "%h", "message": "%s", "author": "%an", "date": "%ci"}' -"$LOG_COUNT" 2>/dev/null | python3 -c "
import sys, json
lines = [l.strip() for l in sys.stdin if l.strip()]
items = []
for line in lines:
    try:
        items.append(json.loads(line))
    except:
        pass
print(json.dumps(items))
" 2>/dev/null || echo "[]")
  fi
fi

# Stash
STASH_COUNT=$(git stash list 2>/dev/null | wc -l | tr -d ' ')
STASH_ENTRIES=""
if [ "$STASH_COUNT" -gt 0 ]; then
  STASH_ENTRIES=$((git stash list 2>/dev/null || true) | head -5)
fi

# ─── Diff Data (for --full and --diff modes) ───────────────────
STAGED_DIFF=""
UNSTAGED_DIFF=""
DIFF_MAX="${UMWELT_DIFF_MAX_LINES:-100}"

if [ "$MODE" = "--full" ] || [ "$MODE" = "--diff" ]; then
  if [ "$STAGED_COUNT" -gt 0 ]; then
    STAGED_DIFF=$((git diff --cached --no-color 2>/dev/null || true) | head -"$DIFF_MAX")
  fi
  if [ "$UNSTAGED_COUNT" -gt 0 ]; then
    UNSTAGED_DIFF=$((git diff --no-color 2>/dev/null || true) | head -"$DIFF_MAX")
  fi
fi

# ─── Output ─────────────────────────────────────────────────────
if [ "$OUTPUT_FMT" = "json" ]; then
  # JSON output using jq or python3 fallback
  is_clean=$([ "$STAGED_COUNT" -eq 0 ] && [ "$UNSTAGED_COUNT" -eq 0 ] && [ "$UNTRACKED_COUNT" -eq 0 ] && echo "true" || echo "false")

  if command -v jq &>/dev/null; then
    jq -n \
      --arg repo "$REPO" \
      --arg branch "$BRANCH" \
      --arg head_sha "$HEAD_SHA" \
      --arg upstream "$UPSTREAM" \
      --argjson ahead "$AHEAD" \
      --argjson behind "$BEHIND" \
      --argjson staged_count "$STAGED_COUNT" \
      --argjson unstaged_count "$UNSTAGED_COUNT" \
      --argjson untracked_count "$UNTRACKED_COUNT" \
      --argjson conflict_count "$CONFLICT_COUNT" \
      --argjson stash_count "$STASH_COUNT" \
      --argjson is_clean "$is_clean" \
      --argjson recent_commits "$RECENT_COMMITS_JSON" \
      '{
        repo: $repo,
        branch: $branch,
        head_sha: $head_sha,
        upstream: (if $upstream == "" then null else $upstream end),
        ahead: $ahead,
        behind: $behind,
        staged_count: $staged_count,
        unstaged_count: $unstaged_count,
        untracked_count: $untracked_count,
        conflict_count: $conflict_count,
        stash_count: $stash_count,
        is_clean: $is_clean,
        recent_commits: $recent_commits
      }' 2>/dev/null || echo '{"error": "json generation failed"}'
  else
    python3 -c "
import json, sys

data = {
    'repo': '$REPO',
    'branch': '$BRANCH',
    'head_sha': '$HEAD_SHA',
    'upstream': '$UPSTREAM' or None,
    'ahead': int('$AHEAD'),
    'behind': int('$BEHIND'),
    'staged_count': int('$STAGED_COUNT'),
    'unstaged_count': int('$UNSTAGED_COUNT'),
    'untracked_count': int('$UNTRACKED_COUNT'),
    'conflict_count': int('$CONFLICT_COUNT'),
    'stash_count': int('$STASH_COUNT'),
    'is_clean': int('$STAGED_COUNT') == 0 and int('$UNSTAGED_COUNT') == 0 and int('$UNTRACKED_COUNT') == 0,
    'recent_commits': json.loads('''$RECENT_COMMITS_JSON''' or '[]'),
}

print(json.dumps(data, indent=2))
" 2>/dev/null || echo '{"error": "json serialization failed"}'
  fi
else
  # Text output using centralized functions
  text_header "GIT CONTEXT"
  text_kv "repo" "${REPO} | branch: ${BRANCH} | head: ${HEAD_SHA}"

  if [ -n "$UPSTREAM" ]; then
    text_kv "upstream" "${UPSTREAM} | ahead: ${AHEAD} | behind: ${BEHIND}"
  else
    text_kv "upstream" "(no tracking branch)"
  fi

  text_kv "staged" "${STAGED_COUNT} files | unstaged: ${UNSTAGED_COUNT} files | untracked: ${UNTRACKED_COUNT} files"
  if [ "$CONFLICT_COUNT" -gt 0 ]; then
    text_kv "CONFLICTS" "${CONFLICT_COUNT} files"
  fi

  if [ "$MODE" = "--minimal" ]; then
    text_footer "GIT CONTEXT"
    exit 0
  fi

  # Recent commits
  text_subsection "recent commits (last ${LOG_COUNT})"
  if [ -n "$RECENT_COMMITS" ]; then
    echo "$RECENT_COMMITS"
  else
    echo "(no commits)"
  fi

  if [ "$MODE" = "--full" ] || [ "$MODE" = "--diff" ]; then
    text_subsection "staged diff"
    if [ -n "$STAGED_DIFF" ]; then
      echo "$STAGED_DIFF"
      if [ "$STAGED_COUNT" -gt 0 ]; then
        local_lines=$(echo "$STAGED_DIFF" | wc -l | tr -d ' ')
        if [ "$local_lines" -ge "$DIFF_MAX" ]; then
          echo "... (truncated at ${DIFF_MAX} lines)"
        fi
      fi
    else
      echo "(no staged changes)"
    fi

    text_subsection "unstaged diff"
    if [ -n "$UNSTAGED_DIFF" ]; then
      echo "$UNSTAGED_DIFF"
    else
      echo "(no unstaged changes)"
    fi
  fi

  # Stash
  if [ "$STASH_COUNT" -gt 0 ]; then
    echo ""
    text_kv "stash" "${STASH_COUNT} entries"
    echo "$STASH_ENTRIES"
  fi

  text_footer "GIT CONTEXT"
fi
