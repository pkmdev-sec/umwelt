#!/usr/bin/env bash
# umwelt: Predictive Context Loading (Innovation 9)
# Analyzes user message content to predict which loaders are relevant,
# so only the needed subset runs instead of everything.
#
# Keyword → Loader mapping:
#   git/branch/commit/merge/push/rebase/cherry-pick  → git-context
#   docker/container/service/deploy/compose/k8s       → docker-status
#   test/spec/jest/pytest/mocha/vitest/coverage        → test-status
#   error/bug/debug/fix/crash/stack/trace              → env-summary + test-status
#   api/endpoint/request/curl/fetch/http/rest          → api-health
#   install/dependency/package/npm/pip/cargo/upgrade    → deps-audit
#   build/compile/bundle/webpack/vite/esbuild          → project-summary
#   file/struct/arch/refactor/move/rename              → project-summary
#
# Usage: source this file, then call predict_needed_loaders "user message"

UMWELT_DIR="${UMWELT_DIR:-$HOME/.claude/umwelt}"

# Default minimum score to include a loader
UMWELT_PREDICTOR_MIN_SCORE="${UMWELT_PREDICTOR_MIN_SCORE:-20}"

# ─── Keyword definitions ────────────────────────────────────────
# Each loader has a set of keywords with weights.
# Format: "keyword:weight keyword:weight ..."

_KEYWORDS_GIT="git:50 branch:40 commit:45 merge:40 push:35 pull:30 rebase:40 cherry-pick:35 stash:30 checkout:30 diff:35 log:25 blame:25 tag:25 reset:30 amend:30 squash:30 conflict:40 upstream:30 remote:25 fetch:30 clone:25"
_KEYWORDS_DOCKER="docker:50 container:45 compose:40 service:35 deploy:40 image:30 volume:25 network:25 k8s:35 kubernetes:35 pod:30 helm:25 registry:25 dockerfile:40 swarm:25"
_KEYWORDS_TEST="test:50 tests:45 spec:40 jest:45 pytest:45 mocha:40 vitest:40 coverage:35 assert:30 expect:30 describe:25 should:20 fixture:25 mock:30 stub:25 e2e:30 unit:25 integration:25 failing:35 broken:30 green:20 red:20 tdd:30"
_KEYWORDS_ENV="error:40 bug:45 debug:45 fix:40 crash:45 stack:35 trace:35 segfault:40 panic:40 exception:35 undefined:30 null:20 memory:25 leak:30 slow:25 hang:30 freeze:25 env:30 environment:25 variable:20 config:20"
_KEYWORDS_API="api:50 endpoint:45 request:40 curl:35 fetch:35 http:35 rest:40 graphql:40 grpc:35 webhook:30 route:30 handler:25 middleware:25 status:20 health:30 port:25 server:25 listen:20 socket:25"
_KEYWORDS_DEPS="install:40 dependency:45 package:40 npm:35 pip:35 cargo:35 yarn:30 pnpm:30 brew:25 upgrade:35 update:30 outdated:35 audit:35 vulnerability:40 lock:25 version:20 require:20 import:15"
_KEYWORDS_PROJECT="build:35 compile:35 bundle:30 webpack:30 vite:30 esbuild:25 structure:30 architecture:35 refactor:40 move:25 rename:25 file:20 directory:20 project:25 scaffold:25 init:20 layout:25 organize:25"

# ─── extract_keywords ───────────────────────────────────────────
# Pulls task-relevant keywords from a message (lowercased, deduplicated).
# Args: message
# Output: space-separated lowercase keywords
extract_keywords() {
  local message="${1:-}"

  # Input validation
  if [ -z "$message" ]; then
    echo ""
    return
  fi

  # Lowercase, strip punctuation (keep hyphens), split into words, deduplicate
  echo "$message" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9 -]/ /g' \
    | tr -s ' ' '\n' \
    | sort -u \
    | tr '\n' ' ' \
    | sed 's/ $//'
}

# ─── score_loader_relevance ─────────────────────────────────────
# Scores how relevant a loader is given the extracted keywords.
# Args: loader_name "keyword1 keyword2 ..."
# Output: integer score (0-100)
score_loader_relevance() {
  local loader="${1:-}"
  local keywords="${2:-}"
  local score=0

  # Input validation
  if [ -z "$loader" ]; then
    echo "0"
    return
  fi

  if [ -z "$keywords" ]; then
    echo "0"
    return
  fi

  # Select the right keyword set
  local keyword_defs=""
  case "$loader" in
    git-context)    keyword_defs="$_KEYWORDS_GIT" ;;
    docker-status)  keyword_defs="$_KEYWORDS_DOCKER" ;;
    test-status)    keyword_defs="$_KEYWORDS_TEST" ;;
    env-summary)    keyword_defs="$_KEYWORDS_ENV" ;;
    api-health)     keyword_defs="$_KEYWORDS_API" ;;
    deps-audit)     keyword_defs="$_KEYWORDS_DEPS" ;;
    project-summary) keyword_defs="$_KEYWORDS_PROJECT" ;;
    *)              echo "0"; return ;;
  esac

  # Score each message keyword against the loader's keyword set (case-insensitive)
  for msg_word in $keywords; do
    # Convert to lowercase for matching (keywords already lowercase from extract_keywords)
    local msg_word_lower
    msg_word_lower=$(echo "$msg_word" | tr '[:upper:]' '[:lower:]')
    for kw_entry in $keyword_defs; do
      local kw="${kw_entry%%:*}"
      local weight="${kw_entry#*:}"
      # Ensure weight is numeric
      if ! [[ "$weight" =~ ^[0-9]+$ ]]; then
        continue
      fi
      if [ "$msg_word_lower" = "$kw" ]; then
        score=$((score + weight))
      fi
    done
  done

  # Cap at 100
  if [ "$score" -gt 100 ]; then
    score=100
  fi

  echo "$score"
}

# ─── filter_loaders ─────────────────────────────────────────────
# Filters a list of loaders by minimum relevance score.
# Args: "loader1 loader2 ..." "keyword1 keyword2 ..." [min_score]
# Output: space-separated list of loaders above threshold
filter_loaders() {
  local loaders="${1:-}"
  local keywords="${2:-}"
  local min_score="${3:-$UMWELT_PREDICTOR_MIN_SCORE}"
  local result=""

  # Input validation
  if [ -z "$loaders" ]; then
    echo ""
    return
  fi

  # Validate min_score is numeric
  if ! [[ "$min_score" =~ ^[0-9]+$ ]]; then
    min_score="$UMWELT_PREDICTOR_MIN_SCORE"
  fi

  for loader in $loaders; do
    local score
    score=$(score_loader_relevance "$loader" "$keywords")
    if [ "$score" -ge "$min_score" ]; then
      result="$result $loader"
    fi
  done

  echo "$result" | sed 's/^ //'
}

# ─── predict_needed_loaders ─────────────────────────────────────
# Main entry point: analyzes a user message and returns an ordered list
# of relevant loaders (highest relevance first).
# Args: "user message text"
# Output: space-separated loader names, ordered by relevance score descending
predict_needed_loaders() {
  local message="${1:-}"
  local min_score="${2:-$UMWELT_PREDICTOR_MIN_SCORE}"

  # Input validation
  if [ -z "$message" ]; then
    echo ""
    return
  fi

  # Validate min_score is numeric
  if ! [[ "$min_score" =~ ^[0-9]+$ ]]; then
    min_score="$UMWELT_PREDICTOR_MIN_SCORE"
  fi

  local keywords
  keywords=$(extract_keywords "$message")

  if [ -z "$keywords" ]; then
    echo ""
    return
  fi

  # Score all loaders
  local all_loaders="git-context docker-status test-status env-summary api-health deps-audit project-summary"
  local scored=""

  for loader in $all_loaders; do
    local score
    score=$(score_loader_relevance "$loader" "$keywords")
    # Ensure score is numeric before comparison
    if [[ "$score" =~ ^[0-9]+$ ]] && [ "$score" -ge "$min_score" ]; then
      scored="$scored ${score}:${loader}"
    fi
  done

  if [ -z "$scored" ]; then
    echo ""
    return
  fi

  # Sort by score descending, output loader names only
  echo "$scored" \
    | tr ' ' '\n' \
    | grep -v '^$' \
    | sort -t: -k1 -rn \
    | cut -d: -f2 \
    | tr '\n' ' ' \
    | sed 's/ $//'
}
