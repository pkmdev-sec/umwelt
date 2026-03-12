#!/usr/bin/env bash
# ============================================================================
# token-budget.sh — Token-aware profiling (Innovation 1)
# ============================================================================
# Purpose: Tracks cumulative token usage per session and recommends profile
#          downgrades when budget thresholds are reached. Includes visual
#          budget bars for terminal display.
#
# Usage: source lib/token-budget.sh
#        Call: track_tokens "$text", check_token_budget, get_budget_percentage,
#              should_downgrade "profile", visual_budget_bar [width],
#              budget_status_with_bar
#
# Dependencies: bash 3.2+, date, terminal with color support (optional)
#
# Output: Token count estimates (chars/4 approximation), budget status,
#         recommended profile downgrades. Visual bar with color-coded status
#         (green <50%, cyan 50-75%, yellow 75-90%, red 90%+).
#         Default budget: 10000 tokens, configurable via $UMWELT_TOKEN_BUDGET.
# ============================================================================
set -euo pipefail

UMWELT_DIFF_CACHE_DIR="${UMWELT_DIFF_CACHE_DIR:-$HOME/.claude/umwelt/.cache}"
mkdir -p "$UMWELT_DIFF_CACHE_DIR"

# Default token budget per session (adjustable via --budget flag or env var)
UMWELT_TOKEN_BUDGET="${UMWELT_TOKEN_BUDGET:-10000}"
UMWELT_TOKEN_COUNT_FILE="$UMWELT_DIFF_CACHE_DIR/token-count"

# Estimate token count from text (chars / 4 approximation)
# Usage: tokens=$(estimate_tokens "$text")
estimate_tokens() {
    local text="${1:-}"

    # Handle empty input
    if [ -z "$text" ]; then
        echo "0"
        return
    fi

    local char_count=${#text}
    # Validate char_count is numeric
    if ! [[ "$char_count" =~ ^[0-9]+$ ]]; then
        echo "0"
        return
    fi

    echo $(( char_count / 4 ))
}

# Get cumulative tokens injected this session
# Usage: total=$(get_session_tokens)
get_session_tokens() {
    if [ -f "$UMWELT_TOKEN_COUNT_FILE" ]; then
        local count
        count=$(cat "$UMWELT_TOKEN_COUNT_FILE" 2>/dev/null || echo "0")
        # Validate it's numeric, default to 0 if not
        if [[ "$count" =~ ^[0-9]+$ ]]; then
            echo "$count"
        else
            echo "0"
        fi
    else
        echo "0"
    fi
}

# Add tokens to session counter
# Usage: track_tokens "$output_text"
track_tokens() {
    local text="${1:-}"
    local new_tokens
    new_tokens=$(estimate_tokens "$text")

    # Validate new_tokens is numeric
    if ! [[ "$new_tokens" =~ ^[0-9]+$ ]]; then
        new_tokens=0
    fi

    local current
    current=$(get_session_tokens)

    # Validate current is numeric
    if ! [[ "$current" =~ ^[0-9]+$ ]]; then
        current=0
    fi

    local total=$((current + new_tokens))

    # Ensure cache directory exists
    if [ ! -d "$UMWELT_DIFF_CACHE_DIR" ]; then
        mkdir -p "$UMWELT_DIFF_CACHE_DIR" 2>/dev/null || {
            echo "Error: Failed to create cache directory" >&2
            echo "$total"
            return 1
        }
    fi

    echo "$total" > "$UMWELT_TOKEN_COUNT_FILE" 2>/dev/null || {
        echo "Error: Failed to write token count file" >&2
    }
    echo "$total"
}

# Check remaining token budget
# Usage: remaining=$(check_token_budget)
check_token_budget() {
    local used
    used=$(get_session_tokens)

    # Validate inputs are numeric
    if ! [[ "$used" =~ ^[0-9]+$ ]]; then
        used=0
    fi

    local budget="${UMWELT_TOKEN_BUDGET:-10000}"
    if ! [[ "$budget" =~ ^[0-9]+$ ]]; then
        budget=10000
    fi

    local remaining=$((budget - used))
    if [ "$remaining" -lt 0 ]; then
        remaining=0
    fi
    echo "$remaining"
}

# Get budget usage as percentage
# Usage: pct=$(get_budget_percentage)
get_budget_percentage() {
    local used
    used=$(get_session_tokens)

    # Validate used is numeric
    if ! [[ "$used" =~ ^[0-9]+$ ]]; then
        used=0
    fi

    local budget="${UMWELT_TOKEN_BUDGET:-10000}"
    if ! [[ "$budget" =~ ^[0-9]+$ ]]; then
        budget=10000
    fi

    if [ "$budget" -eq 0 ]; then
        echo "100"
        return
    fi
    echo $(( (used * 100) / budget ))
}

# Determine if profile should be downgraded based on budget usage
# Returns recommended profile name on stdout
# Usage: recommended=$(should_downgrade "current_profile")
should_downgrade() {
    local current_profile="${1:-dev}"
    local pct
    pct=$(get_budget_percentage)

    # Validate pct is numeric
    if ! [[ "$pct" =~ ^[0-9]+$ ]]; then
        pct=0
    fi

    if [ "$pct" -ge 90 ]; then
        # At 90%+ budget: go silent
        echo "silent"
    elif [ "$pct" -ge 75 ]; then
        # At 75%+ budget: use minimal
        case "$current_profile" in
            debug|dev|review|deploy) echo "minimal" ;;
            minimal) echo "minimal" ;;
            *) echo "minimal" ;;
        esac
    elif [ "$pct" -ge 50 ]; then
        # At 50%+ budget: downgrade debug to dev
        case "$current_profile" in
            debug) echo "dev" ;;
            *) echo "$current_profile" ;;
        esac
    else
        # Under 50%: no change
        echo "$current_profile"
    fi
}

# Reset session token counter
# Usage: reset_token_count
reset_token_count() {
    rm -f "$UMWELT_TOKEN_COUNT_FILE" 2>/dev/null || true
}

# Get a budget status line for output
# Usage: budget_status_line
budget_status_line() {
    local used
    used=$(get_session_tokens)
    local remaining
    remaining=$(check_token_budget)
    local pct
    pct=$(get_budget_percentage)
    echo "[tokens: ${used}/${UMWELT_TOKEN_BUDGET} (${pct}% used, ${remaining} remaining)]"
}

# ─── Visual Budget Bar (P1 Feature) ─────────────────────────────

# Generate a visual budget bar for terminal display
# Usage: visual_budget_bar [width]
visual_budget_bar() {
    local width="${1:-40}"

    # Validate width is numeric
    if ! [[ "$width" =~ ^[0-9]+$ ]]; then
        width=40
    fi

    local used
    used=$(get_session_tokens)
    local pct
    pct=$(get_budget_percentage)

    # Validate numeric values
    if ! [[ "$used" =~ ^[0-9]+$ ]]; then used=0; fi
    if ! [[ "$pct" =~ ^[0-9]+$ ]]; then pct=0; fi

    local budget="${UMWELT_TOKEN_BUDGET:-10000}"
    if ! [[ "$budget" =~ ^[0-9]+$ ]]; then budget=10000; fi

    # Calculate filled blocks
    local filled=$((pct * width / 100))
    if [ "$filled" -gt "$width" ]; then filled=$width; fi

    local empty=$((width - filled))
    if [ "$empty" -lt 0 ]; then empty=0; fi

    # Choose color based on usage
    local color=""
    local reset=""
    if [ -t 1 ]; then
        # Only use colors if stdout is a terminal
        reset="\033[0m"
        if [ "$pct" -ge 90 ]; then
            color="\033[1;31m"  # Red (critical)
        elif [ "$pct" -ge 75 ]; then
            color="\033[1;33m"  # Yellow (warning)
        elif [ "$pct" -ge 50 ]; then
            color="\033[1;36m"  # Cyan (moderate)
        else
            color="\033[1;32m"  # Green (healthy)
        fi
    fi

    # Build the bar
    local bar=""
    local i

    # Add filled portion
    i=0
    while [ "$i" -lt "$filled" ]; do
        bar="${bar}█"
        i=$((i + 1))
    done

    # Add empty portion
    i=0
    while [ "$i" -lt "$empty" ]; do
        bar="${bar}░"
        i=$((i + 1))
    done

    # Output the formatted bar
    printf "${color}%s${reset} %3d%% (%d/%d tokens)\n" "$bar" "$pct" "$used" "$budget"
}

# Get a compact budget bar (single line, no newline)
# Usage: compact_budget_bar [width]
compact_budget_bar() {
    local width="${1:-20}"

    # Validate width is numeric
    if ! [[ "$width" =~ ^[0-9]+$ ]]; then
        width=20
    fi

    local pct
    pct=$(get_budget_percentage)

    # Validate pct is numeric
    if ! [[ "$pct" =~ ^[0-9]+$ ]]; then pct=0; fi

    # Calculate filled blocks
    local filled=$((pct * width / 100))
    if [ "$filled" -gt "$width" ]; then filled=$width; fi

    local empty=$((width - filled))
    if [ "$empty" -lt 0 ]; then empty=0; fi

    # Build the bar
    local bar=""
    local i

    i=0
    while [ "$i" -lt "$filled" ]; do
        bar="${bar}█"
        i=$((i + 1))
    done

    i=0
    while [ "$i" -lt "$empty" ]; do
        bar="${bar}░"
        i=$((i + 1))
    done

    printf "[%s] %3d%%" "$bar" "$pct"
}

# Get budget status with visual bar
# Usage: budget_status_with_bar [width]
budget_status_with_bar() {
    local width="${1:-40}"

    echo "Token Budget Status"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    visual_budget_bar "$width"
    echo ""
    budget_status_line
    echo ""

    # Add recommendation if budget is constrained
    local pct
    pct=$(get_budget_percentage)
    if ! [[ "$pct" =~ ^[0-9]+$ ]]; then pct=0; fi

    if [ "$pct" -ge 90 ]; then
        echo "⚠️  WARNING: Budget nearly exhausted! Consider using 'silent' profile."
    elif [ "$pct" -ge 75 ]; then
        echo "⚡ NOTICE: Budget at 75%+, switching to 'minimal' profile recommended."
    elif [ "$pct" -ge 50 ]; then
        echo "ℹ️  INFO: Budget at 50%+, consider lighter profiles if needed."
    fi
}
