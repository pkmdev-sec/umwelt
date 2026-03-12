#!/usr/bin/env bash
# umwelt: Cache-friendly output splitter (Innovation 2)
# Splits context into STABLE (cached) and VOLATILE (always fresh) sections
set -euo pipefail

UMWELT_DIR="${UMWELT_DIR:-$HOME/.claude/umwelt}"
UMWELT_DIFF_CACHE_DIR="${UMWELT_DIFF_CACHE_DIR:-$HOME/.claude/umwelt/.cache}"
mkdir -p "$UMWELT_DIFF_CACHE_DIR"

STABLE_CACHE_FILE="$UMWELT_DIFF_CACHE_DIR/stable-context.cache"
UMWELT_CALL_COUNT_FILE="$UMWELT_DIFF_CACHE_DIR/call-count"

# Source diff engine for change detection
if [ -f "$UMWELT_DIR/lib/diff-engine.sh" ]; then
    source "$UMWELT_DIR/lib/diff-engine.sh"
fi

# ─── STABLE CONTEXT ────────────────────────────────────────────
# Things that never change mid-session: OS, shell, runtimes, pkg managers

format_stable_context() {
    # Return cached version if it exists
    if [ -f "$STABLE_CACHE_FILE" ]; then
        cat "$STABLE_CACHE_FILE"
        return 0
    fi

    local output=""

    # OS info
    local os_name=""
    if [ -f /etc/os-release ]; then
        os_name=$(grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d'"' -f2 || echo "Linux")
    elif command -v sw_vers &>/dev/null; then
        os_name="macOS $(sw_vers -productVersion 2>/dev/null || echo '')"
    else
        os_name=$(uname -s 2>/dev/null || echo "Unknown")
    fi
    output+="os: ${os_name}"$'\n'

    # Shell
    local shell_name
    shell_name=$(basename "${SHELL:-unknown}")
    local shell_ver=""
    case "$shell_name" in
        bash) shell_ver=$("$SHELL" --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1 || echo "") ;;
        zsh)  shell_ver=$("$SHELL" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1 || echo "") ;;
    esac
    output+="shell: ${shell_name} ${shell_ver}"$'\n'

    # Runtimes
    local runtimes=""
    if command -v node &>/dev/null; then
        runtimes+="node/$(node -v 2>/dev/null | tr -d 'v') "
    fi
    if command -v python3 &>/dev/null; then
        runtimes+="python/$(python3 --version 2>/dev/null | awk '{print $2}') "
    fi
    if command -v go &>/dev/null; then
        runtimes+="go/$(go version 2>/dev/null | awk '{print $3}' | tr -d 'go') "
    fi
    if command -v rustc &>/dev/null; then
        runtimes+="rust/$(rustc --version 2>/dev/null | awk '{print $2}') "
    fi
    if command -v ruby &>/dev/null; then
        runtimes+="ruby/$(ruby -v 2>/dev/null | awk '{print $2}') "
    fi
    if command -v java &>/dev/null; then
        runtimes+="java/$(java -version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1) "
    fi
    runtimes="${runtimes% }"
    if [ -n "$runtimes" ]; then
        output+="runtimes: ${runtimes}"$'\n'
    fi

    # Package managers
    local pkg_managers=""
    command -v npm &>/dev/null && pkg_managers+="npm/$(npm -v 2>/dev/null) "
    command -v pnpm &>/dev/null && pkg_managers+="pnpm/$(pnpm -v 2>/dev/null) "
    command -v yarn &>/dev/null && pkg_managers+="yarn/$(yarn -v 2>/dev/null) "
    command -v bun &>/dev/null && pkg_managers+="bun/$(bun -v 2>/dev/null) "
    command -v pip3 &>/dev/null && pkg_managers+="pip/$(pip3 --version 2>/dev/null | awk '{print $2}') "
    command -v cargo &>/dev/null && pkg_managers+="cargo "
    pkg_managers="${pkg_managers% }"
    if [ -n "$pkg_managers" ]; then
        output+="pkg-managers: ${pkg_managers}"$'\n'
    fi

    # Cache it for the rest of the session
    echo "$output" > "$STABLE_CACHE_FILE"
    echo "$output"
}

# ─── VOLATILE CONTEXT ──────────────────────────────────────────
# Things that change frequently: git status, processes, API health, load

format_volatile_context() {
    local output=""

    # Git status (if in a git repo)
    if git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
        local branch
        branch=$(git branch --show-current 2>/dev/null || echo "detached")
        local status_summary
        local modified added deleted untracked
        modified=$(git diff --name-only 2>/dev/null | wc -l | tr -d ' ')
        added=$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
        untracked=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
        output+="git-branch: ${branch}"$'\n'
        output+="git-modified: ${modified} staged: ${added} untracked: ${untracked}"$'\n'
    fi

    # System load
    local load_avg=""
    if [ -f /proc/loadavg ]; then
        load_avg=$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null || echo "")
    elif command -v sysctl &>/dev/null; then
        load_avg=$(sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | xargs || echo "")
    fi
    if [ -n "$load_avg" ]; then
        output+="load: ${load_avg}"$'\n'
    fi

    # Active ports (quick check of common dev ports)
    local active_ports=""
    for port in 3000 5173 8000 8080; do
        if (echo >/dev/tcp/localhost/$port) 2>/dev/null; then
            active_ports+="${port} "
        fi
    done
    active_ports="${active_ports% }"
    if [ -n "$active_ports" ]; then
        output+="active-ports: ${active_ports}"$'\n'
    fi

    echo "$output"
}

# ─── COMBINED OUTPUT ───────────────────────────────────────────
# On first call: output both stable + volatile
# On subsequent calls: output only changed volatile sections

format_cached_output() {
    local call_count=0
    if [ -f "$UMWELT_CALL_COUNT_FILE" ]; then
        call_count=$(cat "$UMWELT_CALL_COUNT_FILE")
    fi
    call_count=$((call_count + 1))
    echo "$call_count" > "$UMWELT_CALL_COUNT_FILE"

    local stable_output
    stable_output=$(format_stable_context)

    local volatile_output
    volatile_output=$(format_volatile_context)

    if [ "$call_count" -eq 1 ]; then
        # First call: output everything
        echo "=== STABLE CONTEXT ==="
        echo "$stable_output"
        echo "=== END STABLE CONTEXT ==="
        echo ""
        echo "=== VOLATILE CONTEXT ==="
        echo "$volatile_output"
        echo "=== END VOLATILE CONTEXT ==="
    else
        # Subsequent calls: only output volatile if changed
        if diff_inject "volatile-context" "$volatile_output" 2>/dev/null; then
            local summary
            summary=$(get_diff_summary "volatile-context" "$volatile_output" 2>/dev/null || echo "[volatile: updated]")
            echo "=== VOLATILE CONTEXT (updated) ==="
            echo "$summary"
            echo "$volatile_output"
            echo "=== END VOLATILE CONTEXT ==="
        else
            echo "[context unchanged — skipping injection]"
        fi
    fi
}

# Reset the call counter and stable cache (for new sessions)
reset_cache_split() {
    rm -f "$STABLE_CACHE_FILE" "$UMWELT_CALL_COUNT_FILE" 2>/dev/null || true
}
