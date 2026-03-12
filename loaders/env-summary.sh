#!/usr/bin/env bash
# umwelt: env-summary loader
# Outputs environment info — shell, runtimes, key env vars, disk/memory
# Usage: umwelt env-summary [--full|--minimal|--json]
set -euo pipefail

# Source config and output systems
UMWELT_DIR="${UMWELT_DIR:-$HOME/.claude/umwelt}"
if [ -f "$UMWELT_DIR/lib/config.sh" ]; then
  source "$UMWELT_DIR/lib/config.sh"
fi
if [ -f "$UMWELT_DIR/lib/output.sh" ]; then
  source "$UMWELT_DIR/lib/output.sh"
fi

MODE="${1:-default}"
OUTPUT_FMT="${UMWELT_OUTPUT_FORMAT:-text}"
for arg in "$@"; do
  if [ "$arg" = "--json" ]; then OUTPUT_FMT="json"; fi
done

# ─── Gather System Info ──────────────────────────────────────────
OS_NAME=$(uname -s)
OS_RELEASE=$(uname -r)
OS_ARCH=$(uname -m)
SHELL_PATH="${SHELL:-unknown}"
SHELL_VER=$(${SHELL:-bash} --version 2>/dev/null | head -1 | sed 's/.*version /v/' | cut -d'(' -f1 || echo "unknown")
CURRENT_USER="${USER:-$(whoami)}"
CWD="$(pwd)"

# ─── Runtimes ─────────────────────────────────────────────────────
declare -a RUNTIMES=()
if command -v node &>/dev/null; then RUNTIMES+=("node/$(node -v 2>/dev/null | tr -d 'v')"); fi
if command -v bun &>/dev/null; then RUNTIMES+=("bun/$(bun -v 2>/dev/null)"); fi
if command -v python3 &>/dev/null; then RUNTIMES+=("python/$(python3 -V 2>/dev/null | cut -d' ' -f2)"); fi
if command -v go &>/dev/null; then RUNTIMES+=("go/$(go version 2>/dev/null | awk '{print $3}' | tr -d 'go')"); fi
if command -v rustc &>/dev/null; then RUNTIMES+=("rust/$(rustc -V 2>/dev/null | awk '{print $2}')"); fi
if command -v swift &>/dev/null; then RUNTIMES+=("swift/$(swift -version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?')"); fi
if command -v docker &>/dev/null; then RUNTIMES+=("docker/$(docker -v 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"); fi

# ─── Package Managers ─────────────────────────────────────────────
declare -a PKGMGRS=()
if command -v npm &>/dev/null; then PKGMGRS+=("npm/$(npm -v 2>/dev/null)"); fi
if command -v pnpm &>/dev/null; then PKGMGRS+=("pnpm/$(pnpm -v 2>/dev/null)"); fi
if command -v yarn &>/dev/null; then PKGMGRS+=("yarn/$(yarn -v 2>/dev/null)"); fi
if command -v pip3 &>/dev/null; then PKGMGRS+=("pip/$(pip3 -V 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)"); fi
if command -v cargo &>/dev/null; then PKGMGRS+=("cargo/$(cargo -V 2>/dev/null | awk '{print $2}')"); fi
if command -v brew &>/dev/null; then PKGMGRS+=("brew"); fi

# ─── Project Detection ────────────────────────────────────────────
PROJECT_NAME=""
PROJECT_VERSION=""
PROJECT_TYPE=""

if [ -f "package.json" ]; then
  if command -v jq &>/dev/null; then
    PROJECT_NAME=$(jq -r '.name // "?"' package.json 2>/dev/null || echo "?")
    PROJECT_VERSION=$(jq -r '.version // "?"' package.json 2>/dev/null || echo "?")
  else
    PROJECT_NAME=$(python3 -c "import json; print(json.load(open('package.json')).get('name','?'))" 2>/dev/null || echo "?")
    PROJECT_VERSION=$(python3 -c "import json; print(json.load(open('package.json')).get('version','?'))" 2>/dev/null || echo "?")
  fi
  PROJECT_TYPE="node"
elif [ -f "Cargo.toml" ]; then
  PROJECT_NAME=$(grep '^name' Cargo.toml 2>/dev/null | head -1 | cut -d'"' -f2)
  PROJECT_TYPE="rust"
elif [ -f "pyproject.toml" ]; then
  PROJECT_NAME=$(grep '^name' pyproject.toml 2>/dev/null | head -1 | cut -d'"' -f2)
  PROJECT_TYPE="python"
elif [ -f "go.mod" ]; then
  PROJECT_NAME=$(head -1 go.mod 2>/dev/null | awk '{print $2}')
  PROJECT_TYPE="go"
elif [ -f "Package.swift" ]; then
  PROJECT_TYPE="swift"
fi

# ─── Claude Env Vars ──────────────────────────────────────────────
ANTHROPIC_KEY_SET="false"
ANTHROPIC_KEY_LEN=0
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  ANTHROPIC_KEY_SET="true"
  ANTHROPIC_KEY_LEN=${#ANTHROPIC_API_KEY}
fi

# ─── Resource Info (full mode) ────────────────────────────────────
DISK_INFO=""
MEMORY_MB=""
LOAD_AVG=""

if [ "$MODE" = "--full" ]; then
  DISK_INFO=$(df -h . 2>/dev/null | tail -1 | awk '{print $4 " free of " $2}')
  if command -v vm_stat &>/dev/null; then
    FREE_PAGES=$(vm_stat 2>/dev/null | grep "Pages free" | awk '{print $3}' | tr -d '.')
    INACTIVE_PAGES=$(vm_stat 2>/dev/null | grep "Pages inactive" | awk '{print $3}' | tr -d '.')
    MEMORY_MB=$(( (${FREE_PAGES:-0} + ${INACTIVE_PAGES:-0}) * 4096 / 1048576 ))
  fi
  LOAD_AVG=$(uptime 2>/dev/null | grep -oE 'load averages?: [0-9.]+ [0-9.]+ [0-9.]+' || echo "")
fi

# ─── Output ──────────────────────────────────────────────────────
if [ "$OUTPUT_FMT" = "json" ]; then
  if command -v jq &>/dev/null; then
    # Build runtimes and package managers objects
    runtimes_json="{"
    first=true
    for r in ${RUNTIMES[@]:-}; do
      if [[ "$r" == *"/"* ]]; then
        name="${r%%/*}"
        ver="${r#*/}"
        [ "$first" = false ] && runtimes_json+=","
        runtimes_json+="\"$name\":\"$ver\""
        first=false
      fi
    done
    runtimes_json+="}"

    pkgmgrs_json="{"
    first=true
    for p in ${PKGMGRS[@]:-}; do
      if [[ "$p" == *"/"* ]]; then
        name="${p%%/*}"
        ver="${p#*/}"
        [ "$first" = false ] && pkgmgrs_json+=","
        pkgmgrs_json+="\"$name\":\"$ver\""
        first=false
      fi
    done
    pkgmgrs_json+="}"

    jq -n \
      --arg os_name "$OS_NAME" \
      --arg os_release "$OS_RELEASE" \
      --arg os_arch "$OS_ARCH" \
      --arg shell_path "$SHELL_PATH" \
      --arg shell_ver "$SHELL_VER" \
      --arg user "$CURRENT_USER" \
      --arg cwd "$CWD" \
      --argjson runtimes "$runtimes_json" \
      --argjson pkgmgrs "$pkgmgrs_json" \
      --arg proj_name "${PROJECT_NAME:-}" \
      --arg proj_version "${PROJECT_VERSION:-}" \
      --arg proj_type "${PROJECT_TYPE:-}" \
      --argjson api_key_set "$( [ \"$ANTHROPIC_KEY_SET\" = \"true\" ] && echo 'true' || echo 'false' )" \
      --arg model "${ANTHROPIC_MODEL:-}" \
      --arg effort "${CLAUDE_CODE_EFFORT_LEVEL:-}" \
      '{
        os: {name: $os_name, release: $os_release, arch: $os_arch},
        shell: {path: $shell_path, version: $shell_ver},
        user: $user,
        cwd: $cwd,
        runtimes: $runtimes,
        package_managers: $pkgmgrs,
        project: {
          name: (if $proj_name == "" then null else $proj_name end),
          version: (if $proj_version == "" then null else $proj_version end),
          type: (if $proj_type == "" then null else $proj_type end)
        },
        claude_env: {
          api_key_set: $api_key_set,
          model: (if $model == "" then null else $model end),
          effort_level: (if $effort == "" then null else $effort end)
        }
      }' 2>/dev/null || echo '{"error": "json generation failed"}'
  else
    python3 -c "
import json

runtimes_raw = '''${RUNTIMES[*]:-}'''.strip()
pkgmgrs_raw = '''${PKGMGRS[*]:-}'''.strip()

runtimes = {}
for r in runtimes_raw.split():
    if '/' in r:
        name, ver = r.split('/', 1)
        runtimes[name] = ver
    elif r:
        runtimes[r] = 'unknown'

pkgmgrs = {}
for p in pkgmgrs_raw.split():
    if '/' in p:
        name, ver = p.split('/', 1)
        pkgmgrs[name] = ver
    elif p:
        pkgmgrs[p] = 'unknown'

data = {
    'os': {'name': '$OS_NAME', 'release': '$OS_RELEASE', 'arch': '$OS_ARCH'},
    'shell': {'path': '$SHELL_PATH', 'version': '$SHELL_VER'},
    'user': '$CURRENT_USER',
    'cwd': '$CWD',
    'runtimes': runtimes,
    'package_managers': pkgmgrs,
    'project': {
        'name': '${PROJECT_NAME:-}' or None,
        'version': '${PROJECT_VERSION:-}' or None,
        'type': '${PROJECT_TYPE:-}' or None,
    },
    'claude_env': {
        'api_key_set': $( [ \"$ANTHROPIC_KEY_SET\" = \"true\" ] && echo 'True' || echo 'False' ),
        'model': '${ANTHROPIC_MODEL:-}' or None,
        'effort_level': '${CLAUDE_CODE_EFFORT_LEVEL:-}' or None,
    }
}

print(json.dumps(data, indent=2))
" 2>/dev/null || echo '{"error": "json serialization failed"}'
  fi
else
  text_header "ENVIRONMENT"
  text_kv "os" "${OS_NAME} ${OS_RELEASE} (${OS_ARCH})"
  text_kv "shell" "${SHELL_PATH} (${SHELL_VER})"
  text_kv "user" "${CURRENT_USER}"
  text_kv "cwd" "${CWD}"
  text_kv "runtimes" "${RUNTIMES[*]:-none detected}"
  text_kv "pkg-managers" "${PKGMGRS[*]:-none detected}"

  if [ "$MODE" = "--minimal" ]; then
    text_footer "ENVIRONMENT"
    exit 0
  fi

  if [ -n "$PROJECT_TYPE" ]; then
    if [ -n "$PROJECT_VERSION" ]; then
      text_kv "project" "${PROJECT_NAME:-?}@${PROJECT_VERSION} (${PROJECT_TYPE})"
    else
      text_kv "project" "${PROJECT_NAME:-?} (${PROJECT_TYPE})"
    fi
  fi

  text_subsection "claude env"
  if [ "$ANTHROPIC_KEY_SET" = "true" ]; then
    text_kv "ANTHROPIC_API_KEY" "set (${ANTHROPIC_KEY_LEN} chars)"
  else
    text_kv "ANTHROPIC_API_KEY" "not set"
  fi
  if [ -n "${ANTHROPIC_MODEL:-}" ]; then text_kv "ANTHROPIC_MODEL" "${ANTHROPIC_MODEL}"; fi
  if [ -n "${CLAUDE_CODE_EFFORT_LEVEL:-}" ]; then text_kv "CLAUDE_CODE_EFFORT_LEVEL" "${CLAUDE_CODE_EFFORT_LEVEL}"; fi
  if [ -n "${CLAUDE_AUTOCOMPACT_PCT_OVERRIDE:-}" ]; then text_kv "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE" "${CLAUDE_AUTOCOMPACT_PCT_OVERRIDE}"; fi

  if [ "$MODE" = "--full" ]; then
    text_subsection "resources"
    if [ -n "$DISK_INFO" ]; then text_kv "disk" "${DISK_INFO}"; fi
    if [ -n "$MEMORY_MB" ] && [ "$MEMORY_MB" -gt 0 ] 2>/dev/null; then text_kv "memory" "~${MEMORY_MB}MB available"; fi
    if [ -n "$LOAD_AVG" ]; then echo "${LOAD_AVG}"; fi
  fi

  text_footer "ENVIRONMENT"
fi
