#!/usr/bin/env bash
# bang-framework: Diff-based injection engine (Innovation 10)
# Caches previous loader outputs and only injects changes
set -euo pipefail

BANG_DIFF_CACHE_DIR="${BANG_DIFF_CACHE_DIR:-$HOME/.claude/bang-framework/.cache}"
mkdir -p "$BANG_DIFF_CACHE_DIR"

# Check if loader output has changed since last call
# Returns 0 if changed (should inject), 1 if unchanged (skip)
# Usage: diff_inject "loader_name" "$current_output"
diff_inject() {
    local loader_name="$1"
    local current_output="$2"
    local cache_file="$BANG_DIFF_CACHE_DIR/${loader_name}.last"

    if [ -f "$cache_file" ]; then
        local previous
        previous=$(cat "$cache_file")
        if [ "$current_output" = "$previous" ]; then
            # No change — skip injection
            return 1
        fi
    fi

    # Save current for next comparison
    echo "$current_output" > "$cache_file"
    return 0  # Changed — inject
}

# Get a human-readable summary of what changed
# Usage: get_diff_summary "loader_name" "$current_output"
get_diff_summary() {
    local loader_name="$1"
    local current_output="$2"
    local cache_file="$BANG_DIFF_CACHE_DIR/${loader_name}.last"

    if [ -f "$cache_file" ]; then
        local diff_count
        diff_count=$(diff <(cat "$cache_file") <(echo "$current_output") 2>/dev/null | grep -c '^[<>]' || echo "0")
        echo "[$loader_name: $diff_count lines changed]"
    else
        echo "[$loader_name: first scan]"
    fi
}

# Reset all cached outputs
# Usage: reset_cache
reset_cache() {
    rm -f "$BANG_DIFF_CACHE_DIR"/*.last 2>/dev/null || true
}

# Check if a loader has cached output
# Returns 0 if cached, 1 if not
# Usage: has_cache "loader_name"
has_cache() {
    local loader_name="$1"
    local cache_file="$BANG_DIFF_CACHE_DIR/${loader_name}.last"
    [ -f "$cache_file" ]
}

# Get the cached output for a loader
# Usage: cached=$(get_cached "loader_name")
get_cached() {
    local loader_name="$1"
    local cache_file="$BANG_DIFF_CACHE_DIR/${loader_name}.last"
    if [ -f "$cache_file" ]; then
        cat "$cache_file"
    fi
}
