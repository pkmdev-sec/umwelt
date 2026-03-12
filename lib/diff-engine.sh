#!/usr/bin/env bash
# ============================================================================
# diff-engine.sh — Diff-based injection engine (Innovation 10)
# ============================================================================
# Purpose: Caches previous loader outputs and only injects when content
#          changes, achieving 80-90% token savings on repeated calls.
#          Supports cache expiry, size limits, and staleness detection.
#
# Usage: source lib/diff-engine.sh
#        Call: diff_inject "loader_name" "$output" (returns 0 if changed),
#              get_diff_summary, has_cache, get_cached, reset_cache
#
# Dependencies: bash 3.2+, diff, stat
#
# Output: Returns 0 (inject) or 1 (skip) based on content changes.
#         Cache location: $UMWELT_DIFF_CACHE_DIR/*.last
#         Default expiry: 30 minutes, max size: 50MB
# ============================================================================
set -euo pipefail

UMWELT_DIFF_CACHE_DIR="${UMWELT_DIFF_CACHE_DIR:-$HOME/.claude/umwelt/.cache}"
mkdir -p "$UMWELT_DIFF_CACHE_DIR"

# Check if loader output has changed since last call
# Returns 0 if changed (should inject), 1 if unchanged (skip)
# Usage: diff_inject "loader_name" "$current_output"
diff_inject() {
    local loader_name="${1:-}"
    local current_output="${2:-}"

    # Input validation
    if [ -z "$loader_name" ]; then
        echo "Error: diff_inject requires loader_name" >&2
        return 1
    fi

    # Ensure cache directory exists
    if [ ! -d "$UMWELT_DIFF_CACHE_DIR" ]; then
        mkdir -p "$UMWELT_DIFF_CACHE_DIR" 2>/dev/null || {
            echo "Error: Failed to create cache directory: $UMWELT_DIFF_CACHE_DIR" >&2
            return 1
        }
    fi

    local cache_file="$UMWELT_DIFF_CACHE_DIR/${loader_name}.last"

    if [ -f "$cache_file" ]; then
        local previous
        previous=$(cat "$cache_file" 2>/dev/null || echo "")
        if [ "$current_output" = "$previous" ]; then
            # No change — skip injection
            return 1
        fi
    fi

    # Save current for next comparison
    echo "$current_output" > "$cache_file" 2>/dev/null || {
        echo "Error: Failed to write cache file: $cache_file" >&2
        return 1
    }
    return 0  # Changed — inject
}

# Get a human-readable summary of what changed
# Usage: get_diff_summary "loader_name" "$current_output"
get_diff_summary() {
    local loader_name="${1:-}"
    local current_output="${2:-}"

    # Input validation
    if [ -z "$loader_name" ]; then
        echo "[error: missing loader_name]"
        return 1
    fi

    local cache_file="$UMWELT_DIFF_CACHE_DIR/${loader_name}.last"

    if [ -f "$cache_file" ]; then
        local diff_count
        diff_count=$(diff <(cat "$cache_file" 2>/dev/null || echo "") <(echo "$current_output") 2>/dev/null | grep -c '^[<>]' || echo "0")
        echo "[$loader_name: $diff_count lines changed]"
    else
        echo "[$loader_name: first scan]"
    fi
}

# Reset all cached outputs
# Usage: reset_cache
reset_cache() {
    rm -f "$UMWELT_DIFF_CACHE_DIR"/*.last 2>/dev/null || true
}

# Check if a loader has cached output
# Returns 0 if cached, 1 if not
# Usage: has_cache "loader_name"
has_cache() {
    local loader_name="${1:-}"
    if [ -z "$loader_name" ]; then
        return 1
    fi
    local cache_file="$UMWELT_DIFF_CACHE_DIR/${loader_name}.last"
    [ -f "$cache_file" ]
}

# Get the cached output for a loader
# Usage: cached=$(get_cached "loader_name")
get_cached() {
    local loader_name="${1:-}"
    if [ -z "$loader_name" ]; then
        return 1
    fi
    local cache_file="$UMWELT_DIFF_CACHE_DIR/${loader_name}.last"
    if [ -f "$cache_file" ]; then
        cat "$cache_file" 2>/dev/null || true
    fi
}

# ─── Cache Expiry & Size Limits (P1 Feature) ───────────────────

# Default cache expiry in minutes
UMWELT_DIFF_CACHE_EXPIRY="${UMWELT_DIFF_CACHE_EXPIRY:-30}"

# Default max cache size in MB
UMWELT_DIFF_CACHE_MAX_SIZE="${UMWELT_DIFF_CACHE_MAX_SIZE:-50}"

# Check if cache entry is stale (expired)
# Returns 0 if stale, 1 if fresh
# Usage: is_cache_stale "loader_name"
is_cache_stale() {
    local loader_name="${1:-}"
    if [ -z "$loader_name" ]; then
        return 1
    fi

    local cache_file="$UMWELT_DIFF_CACHE_DIR/${loader_name}.last"
    if [ ! -f "$cache_file" ]; then
        return 0  # No cache = stale
    fi

    local now file_age age_minutes
    now=$(date +%s 2>/dev/null || echo 0)

    # Get file modification time (platform-agnostic)
    if stat -f '%m' /dev/null &>/dev/null 2>&1; then
        # macOS
        file_age=$(stat -f '%m' "$cache_file" 2>/dev/null || echo 0)
    else
        # Linux
        file_age=$(stat -c '%Y' "$cache_file" 2>/dev/null || echo 0)
    fi

    # Validate numeric values
    if ! [[ "$now" =~ ^[0-9]+$ ]]; then now=0; fi
    if ! [[ "$file_age" =~ ^[0-9]+$ ]]; then file_age=0; fi

    local age_seconds=$((now - file_age))
    age_minutes=$((age_seconds / 60))

    local expiry="${UMWELT_DIFF_CACHE_EXPIRY:-30}"
    if ! [[ "$expiry" =~ ^[0-9]+$ ]]; then expiry=30; fi

    if [ "$age_minutes" -ge "$expiry" ]; then
        return 0  # Stale
    fi
    return 1  # Fresh
}

# Get cache age in minutes
# Usage: age=$(get_cache_age "loader_name")
get_cache_age() {
    local loader_name="${1:-}"
    if [ -z "$loader_name" ]; then
        echo "0"
        return
    fi

    local cache_file="$UMWELT_DIFF_CACHE_DIR/${loader_name}.last"
    if [ ! -f "$cache_file" ]; then
        echo "999"
        return
    fi

    local now file_age
    now=$(date +%s 2>/dev/null || echo 0)

    if stat -f '%m' /dev/null &>/dev/null 2>&1; then
        file_age=$(stat -f '%m' "$cache_file" 2>/dev/null || echo 0)
    else
        file_age=$(stat -c '%Y' "$cache_file" 2>/dev/null || echo 0)
    fi

    if ! [[ "$now" =~ ^[0-9]+$ ]]; then now=0; fi
    if ! [[ "$file_age" =~ ^[0-9]+$ ]]; then file_age=0; fi

    local age_seconds=$((now - file_age))
    echo $((age_seconds / 60))
}

# Get total cache size in MB
# Usage: size=$(get_cache_size_mb)
get_cache_size_mb() {
    if [ ! -d "$UMWELT_DIFF_CACHE_DIR" ]; then
        echo "0"
        return
    fi

    local size_bytes
    if du -sk "$UMWELT_DIFF_CACHE_DIR" &>/dev/null; then
        size_bytes=$(du -sk "$UMWELT_DIFF_CACHE_DIR" 2>/dev/null | cut -f1 || echo "0")
        echo $((size_bytes / 1024))
    else
        echo "0"
    fi
}

# Clean expired cache entries
# Usage: clean_expired_cache
clean_expired_cache() {
    if [ ! -d "$UMWELT_DIFF_CACHE_DIR" ]; then
        return 0
    fi

    local cleaned=0
    for cache_file in "$UMWELT_DIFF_CACHE_DIR"/*.last; do
        [ -f "$cache_file" ] || continue
        local loader_name
        loader_name=$(basename "$cache_file" .last)
        if is_cache_stale "$loader_name"; then
            rm -f "$cache_file" 2>/dev/null || true
            cleaned=$((cleaned + 1))
        fi
    done
    return 0
}

# Enforce cache size limit by removing oldest entries
# Usage: enforce_cache_size_limit
enforce_cache_size_limit() {
    local max_size="${UMWELT_DIFF_CACHE_MAX_SIZE:-50}"
    if ! [[ "$max_size" =~ ^[0-9]+$ ]]; then max_size=50; fi

    local current_size
    current_size=$(get_cache_size_mb)
    if ! [[ "$current_size" =~ ^[0-9]+$ ]]; then current_size=0; fi

    if [ "$current_size" -le "$max_size" ]; then
        return 0
    fi

    # Remove oldest cache files until under limit
    if [ ! -d "$UMWELT_DIFF_CACHE_DIR" ]; then
        return 0
    fi

    # Get files sorted by age (oldest first)
    local files
    if stat -f '%m' /dev/null &>/dev/null 2>&1; then
        # macOS: use stat -f
        files=$(find "$UMWELT_DIFF_CACHE_DIR" -name "*.last" -type f 2>/dev/null | \
                while read -r f; do
                    echo "$(stat -f '%m' "$f" 2>/dev/null || echo 0) $f"
                done | sort -n | cut -d' ' -f2-)
    else
        # Linux: use stat -c
        files=$(find "$UMWELT_DIFF_CACHE_DIR" -name "*.last" -type f 2>/dev/null | \
                while read -r f; do
                    echo "$(stat -c '%Y' "$f" 2>/dev/null || echo 0) $f"
                done | sort -n | cut -d' ' -f2-)
    fi

    for file in $files; do
        current_size=$(get_cache_size_mb)
        if ! [[ "$current_size" =~ ^[0-9]+$ ]]; then current_size=0; fi

        if [ "$current_size" -le "$max_size" ]; then
            break
        fi
        rm -f "$file" 2>/dev/null || true
    done

    return 0
}

# Enhanced diff_inject with expiry check
# Usage: diff_inject_with_expiry "loader_name" "$current_output"
diff_inject_with_expiry() {
    local loader_name="${1:-}"
    local current_output="${2:-}"

    if [ -z "$loader_name" ]; then
        echo "Error: diff_inject_with_expiry requires loader_name" >&2
        return 1
    fi

    # Check if cache is stale - if so, force inject
    if is_cache_stale "$loader_name"; then
        echo "$current_output" > "$UMWELT_DIFF_CACHE_DIR/${loader_name}.last" 2>/dev/null || true
        enforce_cache_size_limit
        return 0  # Changed — inject
    fi

    # Use regular diff_inject logic
    diff_inject "$loader_name" "$current_output"
    local result=$?

    # If we saved new cache, enforce size limit
    if [ $result -eq 0 ]; then
        enforce_cache_size_limit
    fi

    return $result
}
