#!/usr/bin/env bash
# ============================================================================
# unified-engine.sh — Unified context engine (Innovation 8)
# ============================================================================
# Purpose: Combines Umwelt environment context with Sigil prompt templates
#          into a single optimized injection. Assembles sections by priority,
#          trims to token budget, tracks metrics, and coordinates with all
#          other innovation systems (diff, cost, prediction, relevance).
#
# Usage: source lib/unified-engine.sh
#        Call: assemble_unified_context [event] [user_message]
#              assemble_unified_context_with_metrics
#              get_metrics_summary, is_sigil_active
#
# Dependencies: bash 3.2+, cost-tracker, loader-intelligence, predictor, mktemp
#
# Output: Unified context string with Sigil template (priority 100) first,
#         then stable sections (env, project, deps), then volatile (git, test,
#         docker, api). Max injection: $MAX_INJECTION_TOKENS (4000 default).
#         Metrics tracked: tokens_saved, cache_hits, loaders_skipped.
# ============================================================================
set -euo pipefail

UMWELT_DIR="${UMWELT_DIR:-$HOME/.claude/umwelt}"
LOADERS_DIR="$UMWELT_DIR/loaders"
PROMPT_STUDIO_DIR="${PROMPT_STUDIO_DIR:-$HOME/.claude/prompt-studio}"
TEMPLATES_DIR="$PROMPT_STUDIO_DIR/templates"
UMWELT_CACHE_DIR="${UMWELT_CACHE_DIR:-$HOME/.claude/.bang-cache}"

# Source dependencies
if [ -f "$UMWELT_DIR/lib/config.sh" ]; then
  source "$UMWELT_DIR/lib/config.sh"
fi
if [ -f "$UMWELT_DIR/lib/output.sh" ]; then
  source "$UMWELT_DIR/lib/output.sh"
fi
if [ -f "$UMWELT_DIR/lib/cost-tracker.sh" ]; then
  source "$UMWELT_DIR/lib/cost-tracker.sh"
fi
if [ -f "$UMWELT_DIR/lib/loader-intelligence.sh" ]; then
  source "$UMWELT_DIR/lib/loader-intelligence.sh"
fi

# Maximum token budget for unified injection
MAX_INJECTION_TOKENS="${UMWELT_MAX_INJECTION_TOKENS:-4000}"

# ─── Priority Lookup (bash 3.2 compatible) ───────────────────
# Returns priority number for a section name
get_section_priority() {
  local section="$1"
  case "$section" in
    sigil-template)  echo "100" ;;
    git-context)     echo "90" ;;
    project-summary) echo "85" ;;
    test-status)     echo "60" ;;
    env-summary)     echo "50" ;;
    docker-status)   echo "30" ;;
    api-health)      echo "25" ;;
    deps-audit)      echo "20" ;;
    processes)       echo "10" ;;
    *)               echo "50" ;;
  esac
}

# ─── Sigil Template Detection ───────────────────────────────
get_active_sigil_template() {
  # Gracefully handle missing Sigil installation
  if [ -z "$PROMPT_STUDIO_DIR" ] || [ ! -d "$PROMPT_STUDIO_DIR" ]; then
    echo ""
    return
  fi

  local active_file="$PROMPT_STUDIO_DIR/.active-template"
  if [ -f "$active_file" ]; then
    cat "$active_file" 2>/dev/null || echo ""
  else
    echo ""
  fi
}

# Load Sigil template content (markdown body, skip YAML frontmatter)
load_sigil_template() {
  local template_name="${1:-}"

  # Input validation
  if [ -z "$template_name" ]; then
    return
  fi

  # Gracefully handle missing templates directory
  if [ -z "$TEMPLATES_DIR" ] || [ ! -d "$TEMPLATES_DIR" ]; then
    return
  fi

  local template_file="$TEMPLATES_DIR/${template_name}.md"

  if [ ! -f "$template_file" ]; then
    template_file="$TEMPLATES_DIR/$template_name"
    if [ ! -f "$template_file" ]; then
      return
    fi
  fi

  local in_frontmatter=false
  local frontmatter_count=0
  while IFS= read -r line; do
    if [ "$line" = "---" ]; then
      frontmatter_count=$((frontmatter_count + 1))
      if [ "$frontmatter_count" -ge 2 ]; then
        in_frontmatter=false
        continue
      fi
      in_frontmatter=true
      continue
    fi
    if [ "$in_frontmatter" = "false" ] && [ "$frontmatter_count" -ge 2 ]; then
      echo "$line"
    fi
  done < "$template_file" 2>/dev/null || true
}

# ─── Stable vs Volatile Context ─────────────────────────────
get_stable_context() {
  # Ensure cache directory exists
  if [ ! -d "$UMWELT_CACHE_DIR" ]; then
    mkdir -p "$UMWELT_CACHE_DIR" 2>/dev/null || {
      echo "Error: Failed to create cache directory" >&2
      # Return minimal context if cache fails
      echo "os: $(uname -s 2>/dev/null || echo 'unknown')"
      return
    }
  fi

  local cache_file="$UMWELT_CACHE_DIR/stable-context"
  local cache_ttl=600

  if [ -f "$cache_file" ]; then
    local now file_age age
    now=$(date +%s 2>/dev/null || echo 0)
    if stat -f '%m' /dev/null &>/dev/null 2>&1; then
      file_age=$(stat -f '%m' "$cache_file" 2>/dev/null || echo 0)
    else
      file_age=$(stat -c '%Y' "$cache_file" 2>/dev/null || echo 0)
    fi
    # Validate numeric values
    if [[ "$now" =~ ^[0-9]+$ ]] && [[ "$file_age" =~ ^[0-9]+$ ]]; then
      age=$((now - file_age))
      if [ "$age" -lt "$cache_ttl" ]; then
        cat "$cache_file" 2>/dev/null || true
        return
      fi
    fi
  fi

  local stable=""
  stable="os: $(uname -s) $(uname -r) ($(uname -m))
shell: ${SHELL:-unknown}
user: ${USER:-$(whoami)}
cwd: $(pwd)
"

  local runtimes=""
  command -v node &>/dev/null && runtimes="${runtimes}node/$(node -v 2>/dev/null | tr -d 'v') "
  command -v python3 &>/dev/null && runtimes="${runtimes}python/$(python3 -V 2>/dev/null | cut -d' ' -f2) "
  command -v go &>/dev/null && runtimes="${runtimes}go/$(go version 2>/dev/null | awk '{print $3}' | tr -d 'go') "
  command -v rustc &>/dev/null && runtimes="${runtimes}rust/$(rustc -V 2>/dev/null | awk '{print $2}') "
  if [ -n "$runtimes" ]; then
    stable="${stable}runtimes: ${runtimes}
"
  fi

  mkdir -p "$UMWELT_CACHE_DIR" 2>/dev/null || true
  printf '%s' "$stable" > "$cache_file" 2>/dev/null || true
  printf '%s' "$stable"
}

get_volatile_context() {
  local volatile=""

  if git rev-parse --is-inside-work-tree &>/dev/null; then
    local branch head staged unstaged
    branch=$(git branch --show-current 2>/dev/null || echo "detached")
    head=$(git rev-parse --short HEAD 2>/dev/null || echo "none")
    staged=$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
    unstaged=$(git diff --name-only 2>/dev/null | wc -l | tr -d ' ')
    volatile="git: ${branch}@${head} | staged:${staged} unstaged:${unstaged}
"

    if [ "$staged" -gt 0 ]; then
      volatile="${volatile}staged-files: $(git diff --cached --name-only 2>/dev/null | head -5 | tr '\n' ' ')
"
    fi
    if [ "$unstaged" -gt 0 ]; then
      volatile="${volatile}changed-files: $(git diff --name-only 2>/dev/null | head -5 | tr '\n' ' ')
"
    fi
  fi

  printf '%s' "$volatile"
}

# ─── Priority Order ─────────────────────────────────────────
get_priority_order() {
  echo "sigil-template"
  echo "git-context"
  echo "project-summary"
  echo "test-status"
  echo "env-summary"
  echo "docker-status"
  echo "api-health"
  echo "deps-audit"
  echo "processes"
}

# ─── Token Estimation ───────────────────────────────────────
estimate_text_tokens() {
  local text="${1:-}"
  if [ -z "$text" ]; then
    echo "0"
    return
  fi
  local chars=${#text}
  local words
  words=$(echo "$text" | wc -w 2>/dev/null | tr -d ' ' || echo "0")

  # Validate numeric values before arithmetic
  if ! [[ "$chars" =~ ^[0-9]+$ ]]; then
    chars=0
  fi
  if ! [[ "$words" =~ ^[0-9]+$ ]]; then
    words=0
  fi

  local char_est=$((chars / 4))
  local word_est=$(( (words * 13) / 10 ))
  local avg=$(( (char_est + word_est) / 2 ))
  if [ "$avg" -lt 1 ]; then avg=1; fi
  echo "$avg"
}

# ─── Main Assembly Function ─────────────────────────────────
# Uses temp files instead of arrays for bash 3.2 compatibility
assemble_unified_context() {
  local event_type="${1:-UserPromptSubmit}"
  local user_message="${2:-}"

  # Check cost budget
  if ! should_inject 2>/dev/null; then
    local cost_line
    cost_line=$(format_cost_summary 2>/dev/null || echo "[Umwelt: budget exceeded]")
    echo "$cost_line"
    return
  fi

  local cost_profile
  cost_profile=$(get_cost_profile 2>/dev/null || echo "full")

  # Use temp dir for section storage (bash 3.2 compatible)
  local tmpdir
  tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/umwelt-unified.XXXXXX")
  trap "rm -rf '$tmpdir'" EXIT

  local section_count=0
  local total_tokens=0

  # Helper: add a section
  _add_section() {
    local name="${1:-}"
    local priority="${2:-50}"
    local content="${3:-}"

    # Validate inputs
    if [ -z "$name" ]; then
      return
    fi

    # Validate priority is numeric
    if ! [[ "$priority" =~ ^[0-9]+$ ]]; then
      priority=50
    fi

    local tokens
    tokens=$(estimate_text_tokens "$content")

    # Validate tokens is numeric
    if ! [[ "$tokens" =~ ^[0-9]+$ ]]; then
      tokens=0
    fi

    echo "$name" > "$tmpdir/sec_${section_count}_name" 2>/dev/null || return
    echo "$priority" > "$tmpdir/sec_${section_count}_pri" 2>/dev/null || return
    printf '%s' "$content" > "$tmpdir/sec_${section_count}_content" 2>/dev/null || return
    echo "$tokens" > "$tmpdir/sec_${section_count}_tokens" 2>/dev/null || return
    total_tokens=$((total_tokens + tokens))
    section_count=$((section_count + 1))
  }

  # ── 1. Sigil template behavioral instructions ──
  local sigil_template
  sigil_template=$(get_active_sigil_template)
  if [ -n "$sigil_template" ]; then
    local sigil_content
    sigil_content=$(load_sigil_template "$sigil_template")
    if [ -n "$sigil_content" ]; then
      _add_section "sigil-template" "100" "$sigil_content"
    fi
  fi

  # ── 2. Bang stable environment (cached) ──
  local stable_ctx
  stable_ctx=$(get_stable_context)
  if [ -n "$stable_ctx" ]; then
    local wrapped
    wrapped="=== ENVIRONMENT (stable) ===
${stable_ctx}=== END ENVIRONMENT ==="
    _add_section "env-summary" "50" "$wrapped"
  fi

  # ── 3. Bang volatile environment (diff-based) ──
  local volatile_ctx
  volatile_ctx=$(get_volatile_context)
  if [ -n "$volatile_ctx" ]; then
    local wrapped
    wrapped="=== GIT CONTEXT (volatile) ===
${volatile_ctx}=== END GIT CONTEXT ==="
    _add_section "git-context" "90" "$wrapped"
  fi

  # ── 4. Predict and run relevant loaders ──
  if [ "$cost_profile" != "minimal" ]; then
    local predicted_loaders
    predicted_loaders=$(predict_relevant_loaders "$user_message" 2>/dev/null || echo "")

    for loader in $predicted_loaders; do
      case "$loader" in
        git-context|env-summary) continue ;;
      esac

      if ! is_loader_allowed "$loader" 2>/dev/null; then
        continue
      fi

      if ! is_loader_relevant "$loader" 2>/dev/null; then
        continue
      fi

      local est_tokens
      est_tokens=$(estimate_loader_tokens "$loader" 2>/dev/null || echo "100")

      # Validate est_tokens is numeric
      if ! [[ "$est_tokens" =~ ^[0-9]+$ ]]; then
        est_tokens=100
      fi

      # Validate total_tokens is numeric
      if ! [[ "$total_tokens" =~ ^[0-9]+$ ]]; then
        total_tokens=0
      fi

      if [ $((total_tokens + est_tokens)) -gt "$MAX_INJECTION_TOKENS" ]; then
        continue
      fi

      local loader_path="$LOADERS_DIR/${loader}.sh"
      if [ -f "$loader_path" ]; then
        local raw_output
        raw_output=$("$loader_path" 2>/dev/null) || true
        local formatted
        formatted=$(format_loader_output "$loader" "$raw_output" 2>/dev/null || echo "$raw_output")
        if [ -n "$formatted" ]; then
          local pri
          pri=$(get_section_priority "$loader")
          _add_section "$loader" "$pri" "$formatted"
        fi
      fi
    done
  fi

  # ── 5. Trim if over budget ──
  if [ "$total_tokens" -gt "$MAX_INJECTION_TOKENS" ]; then
    # Build priority list and sort ascending
    local pri_list=""
    local i=0
    while [ "$i" -lt "$section_count" ]; do
      local pri
      pri=$(cat "$tmpdir/sec_${i}_pri")
      pri_list="${pri_list}${i}:${pri}
"
      i=$((i + 1))
    done

    local sorted_list
    sorted_list=$(echo "$pri_list" | sort -t: -k2 -n)

    echo "$sorted_list" | while IFS=: read -r idx pri; do
      [ -z "$idx" ] && continue
      if [ "$pri" -ge 100 ]; then
        continue
      fi
      if [ "$total_tokens" -le "$MAX_INJECTION_TOKENS" ]; then
        break
      fi
      local removed_tokens
      removed_tokens=$(cat "$tmpdir/sec_${idx}_tokens")
      total_tokens=$((total_tokens - removed_tokens))
      : > "$tmpdir/sec_${idx}_content"
    done
  fi

  # ── 6. Assemble output: sigil → stable → volatile ──
  local output=""

  # Sigil template first
  local i=0
  while [ "$i" -lt "$section_count" ]; do
    local name
    name=$(cat "$tmpdir/sec_${i}_name")
    if [ "$name" = "sigil-template" ]; then
      local content
      content=$(cat "$tmpdir/sec_${i}_content")
      if [ -n "$content" ]; then
        output="${output}${content}

"
      fi
    fi
    i=$((i + 1))
  done

  # Stable sections
  i=0
  while [ "$i" -lt "$section_count" ]; do
    local name
    name=$(cat "$tmpdir/sec_${i}_name")
    case "$name" in
      env-summary|project-summary|deps-audit)
        local content
        content=$(cat "$tmpdir/sec_${i}_content")
        if [ -n "$content" ]; then
          output="${output}${content}

"
        fi
        ;;
    esac
    i=$((i + 1))
  done

  # Volatile sections
  i=0
  while [ "$i" -lt "$section_count" ]; do
    local name
    name=$(cat "$tmpdir/sec_${i}_name")
    case "$name" in
      git-context|test-status|docker-status|api-health)
        local content
        content=$(cat "$tmpdir/sec_${i}_content")
        if [ -n "$content" ]; then
          output="${output}${content}

"
        fi
        ;;
    esac
    i=$((i + 1))
  done

  # ── 7. Track cost ──
  local cost_line=""
  if type track_injection &>/dev/null 2>&1; then
    cost_line=$(track_injection "$output" 2>/dev/null || true)
  fi

  # ── 8. Output ──
  printf '%s' "$output"

  if [ -n "$cost_line" ]; then
    echo "$cost_line"
  fi
}

# ─── Sigil Status Check ─────────────────────────────────────
is_sigil_active() {
  local template
  template=$(get_active_sigil_template)
  [ -n "$template" ]
}

# ─── Metrics Output (P1 Feature) ─────────────────────────────

UMWELT_METRICS_FILE="${UMWELT_CACHE_DIR:-$HOME/.claude/.bang-cache}/unified-metrics"

# Initialize metrics tracking
_init_metrics() {
  if [ ! -d "$UMWELT_CACHE_DIR" ]; then
    mkdir -p "$UMWELT_CACHE_DIR" 2>/dev/null || return 1
  fi

  if [ ! -f "$UMWELT_METRICS_FILE" ]; then
    echo "tokens_saved:0" > "$UMWELT_METRICS_FILE" 2>/dev/null || true
    echo "cache_hits:0" >> "$UMWELT_METRICS_FILE" 2>/dev/null || true
    echo "cache_misses:0" >> "$UMWELT_METRICS_FILE" 2>/dev/null || true
    echo "loaders_skipped:0" >> "$UMWELT_METRICS_FILE" 2>/dev/null || true
    echo "loaders_run:0" >> "$UMWELT_METRICS_FILE" 2>/dev/null || true
    echo "injections:0" >> "$UMWELT_METRICS_FILE" 2>/dev/null || true
  fi
}

# Get metric value
# Usage: value=$(get_metric "metric_name")
get_metric() {
  local metric="${1:-}"
  if [ -z "$metric" ]; then
    echo "0"
    return
  fi

  _init_metrics

  if [ -f "$UMWELT_METRICS_FILE" ]; then
    local value
    value=$(grep "^${metric}:" "$UMWELT_METRICS_FILE" 2>/dev/null | cut -d: -f2 || echo "0")
    if [[ "$value" =~ ^[0-9]+$ ]]; then
      echo "$value"
    else
      echo "0"
    fi
  else
    echo "0"
  fi
}

# Increment metric
# Usage: increment_metric "metric_name" [amount]
increment_metric() {
  local metric="${1:-}"
  local amount="${2:-1}"

  if [ -z "$metric" ]; then
    return 1
  fi

  if ! [[ "$amount" =~ ^[0-9]+$ ]]; then
    amount=1
  fi

  _init_metrics

  local current
  current=$(get_metric "$metric")
  if ! [[ "$current" =~ ^[0-9]+$ ]]; then
    current=0
  fi

  local new_value=$((current + amount))

  # Update metrics file
  if [ -f "$UMWELT_METRICS_FILE" ]; then
    local tmpfile
    tmpfile=$(mktemp)
    grep -v "^${metric}:" "$UMWELT_METRICS_FILE" > "$tmpfile" 2>/dev/null || true
    echo "${metric}:${new_value}" >> "$tmpfile"
    mv "$tmpfile" "$UMWELT_METRICS_FILE" 2>/dev/null || true
  fi
}

# Record tokens saved by caching/skipping
# Usage: record_tokens_saved amount
record_tokens_saved() {
  local amount="${1:-0}"
  if ! [[ "$amount" =~ ^[0-9]+$ ]]; then
    amount=0
  fi
  increment_metric "tokens_saved" "$amount"
}

# Record cache hit
# Usage: record_cache_hit
record_cache_hit() {
  increment_metric "cache_hits" 1
}

# Record cache miss
# Usage: record_cache_miss
record_cache_miss() {
  increment_metric "cache_misses" 1
}

# Record loader skipped
# Usage: record_loader_skipped
record_loader_skipped() {
  increment_metric "loaders_skipped" 1
}

# Record loader run
# Usage: record_loader_run
record_loader_run() {
  increment_metric "loaders_run" 1
}

# Record injection
# Usage: record_injection
record_injection() {
  increment_metric "injections" 1
}

# Get metrics summary
# Usage: get_metrics_summary
get_metrics_summary() {
  _init_metrics

  local tokens_saved cache_hits cache_misses loaders_skipped loaders_run injections

  tokens_saved=$(get_metric "tokens_saved")
  cache_hits=$(get_metric "cache_hits")
  cache_misses=$(get_metric "cache_misses")
  loaders_skipped=$(get_metric "loaders_skipped")
  loaders_run=$(get_metric "loaders_run")
  injections=$(get_metric "injections")

  # Validate all are numeric
  if ! [[ "$tokens_saved" =~ ^[0-9]+$ ]]; then tokens_saved=0; fi
  if ! [[ "$cache_hits" =~ ^[0-9]+$ ]]; then cache_hits=0; fi
  if ! [[ "$cache_misses" =~ ^[0-9]+$ ]]; then cache_misses=0; fi
  if ! [[ "$loaders_skipped" =~ ^[0-9]+$ ]]; then loaders_skipped=0; fi
  if ! [[ "$loaders_run" =~ ^[0-9]+$ ]]; then loaders_run=0; fi
  if ! [[ "$injections" =~ ^[0-9]+$ ]]; then injections=0; fi

  # Calculate cache hit rate
  local total_cache=$((cache_hits + cache_misses))
  local hit_rate=0
  if [ "$total_cache" -gt 0 ]; then
    hit_rate=$(( (cache_hits * 100) / total_cache ))
  fi

  echo "Umwelt Metrics Summary"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Tokens saved:      $tokens_saved"
  echo "Cache hits:        $cache_hits"
  echo "Cache misses:      $cache_misses"
  echo "Cache hit rate:    ${hit_rate}%"
  echo "Loaders run:       $loaders_run"
  echo "Loaders skipped:   $loaders_skipped"
  echo "Total injections:  $injections"

  if [ "$loaders_skipped" -gt 0 ] && [ "$loaders_run" -gt 0 ]; then
    local skip_rate=$(( (loaders_skipped * 100) / (loaders_skipped + loaders_run) ))
    echo "Loader skip rate:  ${skip_rate}%"
  fi
}

# Get compact metrics output (single line)
# Usage: compact_metrics
compact_metrics() {
  local tokens_saved cache_hits loaders_skipped

  tokens_saved=$(get_metric "tokens_saved")
  cache_hits=$(get_metric "cache_hits")
  loaders_skipped=$(get_metric "loaders_skipped")

  echo "[metrics: ${tokens_saved} tokens saved, ${cache_hits} cache hits, ${loaders_skipped} loaders skipped]"
}

# Reset all metrics
# Usage: reset_metrics
reset_metrics() {
  rm -f "$UMWELT_METRICS_FILE" 2>/dev/null || true
  _init_metrics
  echo "Metrics reset"
}

# Enhanced assemble with metrics tracking
assemble_unified_context_with_metrics() {
  local event_type="${1:-UserPromptSubmit}"
  local user_message="${2:-}"

  # Track injection
  record_injection

  # Call original assemble function
  assemble_unified_context "$event_type" "$user_message"
}

# ─── CLI Interface ───────────────────────────────────────────
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-assemble}" in
    assemble)
      assemble_unified_context "${2:-UserPromptSubmit}" "${3:-}"
      ;;
    assemble-with-metrics)
      assemble_unified_context_with_metrics "${2:-UserPromptSubmit}" "${3:-}"
      ;;
    sigil-status)
      local_template=$(get_active_sigil_template)
      if [ -n "$local_template" ]; then
        echo "active: $local_template"
      else
        echo "inactive"
      fi
      ;;
    priority-order)
      get_priority_order
      ;;
    stable)
      get_stable_context
      ;;
    volatile)
      get_volatile_context
      ;;
    metrics)
      get_metrics_summary
      ;;
    compact-metrics)
      compact_metrics
      ;;
    reset-metrics)
      reset_metrics
      ;;
    *)
      echo "Usage: unified-engine.sh {assemble|assemble-with-metrics|sigil-status|priority-order|stable|volatile|metrics|compact-metrics|reset-metrics}" >&2
      echo "  assemble [event] [message]       — assemble unified context" >&2
      echo "  assemble-with-metrics [e] [m]    — assemble with metrics tracking" >&2
      echo "  sigil-status                     — check if Sigil template is active" >&2
      echo "  priority-order                   — show section trimming priority" >&2
      echo "  stable                           — show stable context (cached)" >&2
      echo "  volatile                         — show volatile context (live)" >&2
      echo "  metrics                          — show metrics summary" >&2
      echo "  compact-metrics                  — show compact metrics (one line)" >&2
      echo "  reset-metrics                    — reset all metrics" >&2
      exit 1
      ;;
  esac
fi
