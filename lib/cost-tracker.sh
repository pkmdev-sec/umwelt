#!/usr/bin/env bash
# bang-framework: Cost-Conscious Scanning (Innovation 6)
# Tracks token cost of Bang injections per session with budget thresholds
set -euo pipefail

BANG_DIR="${BANG_DIR:-$HOME/.claude/bang-framework}"
BANG_CACHE_DIR="${BANG_CACHE_DIR:-$HOME/.claude/.bang-cache}"
SESSION_COST_FILE="$BANG_CACHE_DIR/session-cost"
SESSION_LOG_FILE="$BANG_CACHE_DIR/session-cost-log"

# Sonnet default pricing (per million tokens)
PRICE_PER_M_INPUT="${BANG_PRICE_PER_M_INPUT:-3}"
PRICE_PER_M_OUTPUT="${BANG_PRICE_PER_M_OUTPUT:-15}"

# Cost thresholds (in dollars)
THRESHOLD_FULL=0.10
THRESHOLD_REDUCED=0.25
THRESHOLD_MINIMAL=0.50

# ─── Token Estimation ─────────────────────────────────────────
# Approximate: ~4 chars per token (cl100k_base), hybrid with word-based
estimate_tokens() {
  local text="$1"
  if [ -z "$text" ]; then
    echo "0"
    return
  fi
  local chars=${#text}
  local words
  words=$(echo "$text" | wc -w | tr -d ' ')
  local char_est=$((chars / 4))
  local word_est=$(( (words * 13) / 10 ))
  local avg=$(( (char_est + word_est) / 2 ))
  [ "$avg" -lt 1 ] && avg=1
  echo "$avg"
}

# ─── Cost Estimation ──────────────────────────────────────────
# estimate_injection_cost <text>
# Returns dollar amount as a decimal string
estimate_injection_cost() {
  local text="$1"
  local tokens
  tokens=$(estimate_tokens "$text")

  # Cost = tokens * (price_per_million / 1_000_000)
  # Use awk for floating point
  awk -v tokens="$tokens" -v price="$PRICE_PER_M_INPUT" \
    'BEGIN { printf "%.6f", (tokens / 1000000) * price }'
}

# ─── Session Cost Management ─────────────────────────────────
_init_session_cost() {
  mkdir -p "$BANG_CACHE_DIR"
  if [ ! -f "$SESSION_COST_FILE" ]; then
    echo "0.000000" > "$SESSION_COST_FILE"
  fi
}

# get_session_cost — returns cumulative cost
get_session_cost() {
  _init_session_cost
  cat "$SESSION_COST_FILE"
}

# Add cost to running total
add_session_cost() {
  local amount="$1"
  _init_session_cost
  local current
  current=$(cat "$SESSION_COST_FILE")
  local new_total
  new_total=$(awk -v c="$current" -v a="$amount" 'BEGIN { printf "%.6f", c + a }')
  echo "$new_total" > "$SESSION_COST_FILE"

  # Log the injection
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "$timestamp | +$amount | total=$new_total" >> "$SESSION_LOG_FILE"

  echo "$new_total"
}

# Reset session cost (e.g., on new session)
reset_session_cost() {
  mkdir -p "$BANG_CACHE_DIR"
  echo "0.000000" > "$SESSION_COST_FILE"
  : > "$SESSION_LOG_FILE"
}

# ─── Cost Profile ────────────────────────────────────────────
# get_cost_profile — returns full/reduced/minimal/silent
get_cost_profile() {
  local cost
  cost=$(get_session_cost)

  awk -v cost="$cost" \
      -v t_full="$THRESHOLD_FULL" \
      -v t_reduced="$THRESHOLD_REDUCED" \
      -v t_minimal="$THRESHOLD_MINIMAL" \
    'BEGIN {
      if (cost < t_full) print "full"
      else if (cost < t_reduced) print "reduced"
      else if (cost < t_minimal) print "minimal"
      else print "silent"
    }'
}

# ─── Should Inject ───────────────────────────────────────────
# should_inject — returns 0 (true) if injection allowed, 1 (false) if silent
should_inject() {
  local profile
  profile=$(get_cost_profile)
  if [ "$profile" = "silent" ]; then
    return 1
  fi
  return 0
}

# ─── Loader Filtering by Cost Profile ────────────────────────
# get_allowed_loaders <profile>
# Returns space-separated list of allowed loader names
get_allowed_loaders() {
  local profile="${1:-$(get_cost_profile)}"

  case "$profile" in
    full)
      echo "git-context env-summary test-status docker-status api-health deps-audit project-summary"
      ;;
    reduced)
      # Skip non-essential: docker-status, api-health, deps-audit
      echo "git-context env-summary test-status project-summary"
      ;;
    minimal)
      # Only git + cwd
      echo "git-context project-summary"
      ;;
    silent)
      echo ""
      ;;
  esac
}

# Check if a specific loader is allowed under current budget
is_loader_allowed() {
  local loader_name="$1"
  local allowed
  allowed=$(get_allowed_loaders)

  case " $allowed " in
    *" $loader_name "*) return 0 ;;
    *) return 1 ;;
  esac
}

# ─── Budget Percentage ───────────────────────────────────────
# Returns percentage of silent threshold consumed
get_budget_pct() {
  local cost
  cost=$(get_session_cost)
  awk -v cost="$cost" -v max="$THRESHOLD_MINIMAL" \
    'BEGIN { printf "%d", (cost / max) * 100 }'
}

# ─── Cost Summary Line ──────────────────────────────────────
# Output cost summary as a compact status line
format_cost_summary() {
  local cost
  cost=$(get_session_cost)
  local pct
  pct=$(get_budget_pct)
  local profile
  profile=$(get_cost_profile)

  printf "[Bang cost: \$%.2f | Budget: %s%% | Mode: %s]" \
    "$(awk -v c="$cost" 'BEGIN { printf "%.2f", c }')" \
    "$pct" \
    "$profile"
}

# ─── Track and Report ────────────────────────────────────────
# Main function: estimate cost, add to session, return summary
track_injection() {
  local text="$1"
  local cost
  cost=$(estimate_injection_cost "$text")
  add_session_cost "$cost" > /dev/null
  format_cost_summary
}

# ─── CLI Interface ───────────────────────────────────────────
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-status}" in
    estimate)
      if [ -n "${2:-}" ]; then
        estimate_injection_cost "$2"
      else
        text=$(cat)
        estimate_injection_cost "$text"
      fi
      ;;
    track)
      if [ -n "${2:-}" ]; then
        track_injection "$2"
      else
        text=$(cat)
        track_injection "$text"
      fi
      ;;
    status)
      format_cost_summary
      ;;
    profile)
      get_cost_profile
      ;;
    reset)
      reset_session_cost
      echo "Session cost reset to 0"
      ;;
    should-inject)
      if should_inject; then
        echo "yes"
      else
        echo "no"
      fi
      ;;
    *)
      echo "Usage: cost-tracker.sh {estimate|track|status|profile|reset|should-inject}" >&2
      exit 1
      ;;
  esac
fi
