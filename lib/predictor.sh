#!/usr/bin/env bash
# ============================================================================
# predictor.sh — Predictive context loading (Innovation 9)
# ============================================================================
# Purpose: Analyzes user message content to predict which loaders are relevant.
#          Uses keyword matching with weighted scoring to avoid running all
#          loaders. Learns from past accuracy to boost/penalize loaders.
#
# Usage: source lib/predictor.sh
#        Call: predict_needed_loaders "user message" [min_score]
#              score_loader_relevance "loader" "keywords"
#              get_accuracy_report, record_loader_used "name"
#
# Dependencies: bash 3.2+, sort, grep
#
# Output: Space-separated list of loader names, ordered by relevance score
#         (highest first). Keyword mappings:
#         git→git-context, docker→docker-status, test→test-status,
#         error/bug→env-summary, api→api-health, install→deps-audit,
#         build→project-summary. Min score: $UMWELT_PREDICTOR_MIN_SCORE (20).
# ============================================================================

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

    # Apply learning boost from past accuracy
    local boost
    boost=$(get_accuracy_boost "$loader")
    if ! [[ "$boost" =~ ^[0-9]+$ ]]; then boost=0; fi
    score=$((score + boost))

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

# ─── Learning from Past Accuracy (P1 Feature) ───────────────────

UMWELT_PREDICTOR_ACCURACY_DIR="${UMWELT_DIFF_CACHE_DIR:-$HOME/.claude/umwelt/.cache}/predictor-accuracy"
mkdir -p "$UMWELT_PREDICTOR_ACCURACY_DIR" 2>/dev/null || true

# Record that a loader was actually used (predicted and injected)
# Usage: record_loader_used "loader_name"
record_loader_used() {
  local loader="${1:-}"
  if [ -z "$loader" ]; then
    return 1
  fi

  if [ ! -d "$UMWELT_PREDICTOR_ACCURACY_DIR" ]; then
    mkdir -p "$UMWELT_PREDICTOR_ACCURACY_DIR" 2>/dev/null || return 1
  fi

  local usage_file="$UMWELT_PREDICTOR_ACCURACY_DIR/${loader}.usage"
  local count=1

  if [ -f "$usage_file" ]; then
    local current
    current=$(cat "$usage_file" 2>/dev/null || echo "0")
    if [[ "$current" =~ ^[0-9]+$ ]]; then
      count=$((current + 1))
    fi
  fi

  echo "$count" > "$usage_file" 2>/dev/null || true
}

# Record that a loader was predicted but NOT used (wasted prediction)
# Usage: record_loader_predicted_unused "loader_name"
record_loader_predicted_unused() {
  local loader="${1:-}"
  if [ -z "$loader" ]; then
    return 1
  fi

  if [ ! -d "$UMWELT_PREDICTOR_ACCURACY_DIR" ]; then
    mkdir -p "$UMWELT_PREDICTOR_ACCURACY_DIR" 2>/dev/null || return 1
  fi

  local miss_file="$UMWELT_PREDICTOR_ACCURACY_DIR/${loader}.misses"
  local count=1

  if [ -f "$miss_file" ]; then
    local current
    current=$(cat "$miss_file" 2>/dev/null || echo "0")
    if [[ "$current" =~ ^[0-9]+$ ]]; then
      count=$((current + 1))
    fi
  fi

  echo "$count" > "$miss_file" 2>/dev/null || true
}

# Get accuracy score for a loader (used / predicted ratio)
# Returns 0-100 (percentage)
# Usage: accuracy=$(get_loader_accuracy "loader_name")
get_loader_accuracy() {
  local loader="${1:-}"
  if [ -z "$loader" ]; then
    echo "50"
    return
  fi

  local usage_file="$UMWELT_PREDICTOR_ACCURACY_DIR/${loader}.usage"
  local miss_file="$UMWELT_PREDICTOR_ACCURACY_DIR/${loader}.misses"

  local used=0
  local missed=0

  if [ -f "$usage_file" ]; then
    used=$(cat "$usage_file" 2>/dev/null || echo "0")
    if ! [[ "$used" =~ ^[0-9]+$ ]]; then used=0; fi
  fi

  if [ -f "$miss_file" ]; then
    missed=$(cat "$miss_file" 2>/dev/null || echo "0")
    if ! [[ "$missed" =~ ^[0-9]+$ ]]; then missed=0; fi
  fi

  local total=$((used + missed))
  if [ "$total" -eq 0 ]; then
    echo "50"  # Default accuracy for new loaders
    return
  fi

  local accuracy=$(( (used * 100) / total ))
  echo "$accuracy"
}

# Get accuracy boost to apply to loader score
# High accuracy loaders get +10, low accuracy get -10
# Usage: boost=$(get_accuracy_boost "loader_name")
get_accuracy_boost() {
  local loader="${1:-}"
  if [ -z "$loader" ]; then
    echo "0"
    return
  fi

  local accuracy
  accuracy=$(get_loader_accuracy "$loader")
  if ! [[ "$accuracy" =~ ^[0-9]+$ ]]; then
    echo "0"
    return
  fi

  # Boost: +10 if >75% accuracy, -10 if <25% accuracy
  if [ "$accuracy" -ge 75 ]; then
    echo "10"
  elif [ "$accuracy" -le 25 ]; then
    echo "-10"
  else
    echo "0"
  fi
}

# Get accuracy report for all loaders
# Usage: get_accuracy_report
get_accuracy_report() {
  if [ ! -d "$UMWELT_PREDICTOR_ACCURACY_DIR" ]; then
    echo "No accuracy data available"
    return
  fi

  echo "Loader Accuracy Report"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  local all_loaders="git-context docker-status test-status env-summary api-health deps-audit project-summary"

  for loader in $all_loaders; do
    local usage_file="$UMWELT_PREDICTOR_ACCURACY_DIR/${loader}.usage"
    local miss_file="$UMWELT_PREDICTOR_ACCURACY_DIR/${loader}.misses"

    local used=0
    local missed=0

    if [ -f "$usage_file" ]; then
      used=$(cat "$usage_file" 2>/dev/null || echo "0")
      if ! [[ "$used" =~ ^[0-9]+$ ]]; then used=0; fi
    fi

    if [ -f "$miss_file" ]; then
      missed=$(cat "$miss_file" 2>/dev/null || echo "0")
      if ! [[ "$missed" =~ ^[0-9]+$ ]]; then missed=0; fi
    fi

    local total=$((used + missed))
    if [ "$total" -eq 0 ]; then
      continue
    fi

    local accuracy
    accuracy=$(get_loader_accuracy "$loader")
    local boost
    boost=$(get_accuracy_boost "$loader")

    printf "%-18s: %3d%% accuracy (%d used, %d wasted) boost: %+d\n" \
           "$loader" "$accuracy" "$used" "$missed" "$boost"
  done
}

# Reset all accuracy tracking
# Usage: reset_accuracy_tracking
reset_accuracy_tracking() {
  rm -rf "${UMWELT_PREDICTOR_ACCURACY_DIR:?}"/* 2>/dev/null || true
}
