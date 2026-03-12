#!/usr/bin/env bash
# umwelt: Intelligent Loaders (Innovation 7)
# Smart loader selection — skip irrelevant loaders, estimate tokens, format output
set -euo pipefail

UMWELT_DIR="${UMWELT_DIR:-$HOME/.claude/umwelt}"
LOADERS_DIR="$UMWELT_DIR/loaders"

# Source config if available
if [ -f "$UMWELT_DIR/lib/config.sh" ]; then
  source "$UMWELT_DIR/lib/config.sh"
fi

# ─── Loader Relevance Detection ──────────────────────────────
# is_loader_relevant <loader_name>
# Returns 0 (true) if the loader would produce useful output, 1 (false) otherwise
is_loader_relevant() {
  local loader_name="${1:-}"

  # Input validation
  if [ -z "$loader_name" ]; then
    return 1
  fi

  case "$loader_name" in
    docker-status)
      # Skip if docker is not installed or not running
      if ! command -v docker &>/dev/null; then
        return 1
      fi
      if ! docker info &>/dev/null 2>&1; then
        return 1
      fi
      return 0
      ;;

    api-health)
      # Skip if no services are responding on common ports
      local has_service=false
      local ports="${UMWELT_LOCAL_PORTS:-3000:dev 8000:api 8080:proxy}"
      for entry in $ports; do
        local port="${entry%%:*}"
        if nc -z localhost "$port" &>/dev/null 2>&1; then
          has_service=true
          break
        fi
      done
      # Also check custom endpoints
      if [ -n "${UMWELT_API_ENDPOINTS:-}" ]; then
        has_service=true
      fi
      if [ "$has_service" = "true" ]; then
        return 0
      fi
      return 1
      ;;

    test-status)
      # Skip if no test framework detected
      local project_dir="${UMWELT_PROJECT_DIR:-.}"
      if [ -f "$project_dir/package.json" ]; then
        if grep -qE '"(vitest|jest|mocha|test)"' "$project_dir/package.json" 2>/dev/null; then
          return 0
        fi
      fi
      if [ -f "$project_dir/pytest.ini" ] || [ -f "$project_dir/pyproject.toml" ] || [ -f "$project_dir/setup.py" ]; then
        return 0
      fi
      if [ -f "$project_dir/Cargo.toml" ] || [ -f "$project_dir/go.mod" ] || [ -f "$project_dir/Package.swift" ]; then
        return 0
      fi
      return 1
      ;;

    deps-audit)
      # Skip if no dependency manifest detected
      local project_dir="${UMWELT_PROJECT_DIR:-.}"
      if [ -f "$project_dir/package.json" ] || [ -f "$project_dir/requirements.txt" ] || \
         [ -f "$project_dir/Cargo.toml" ] || [ -f "$project_dir/go.mod" ] || \
         [ -f "$project_dir/pyproject.toml" ] || [ -f "$project_dir/Gemfile" ]; then
        return 0
      fi
      return 1
      ;;

    git-context)
      # Almost always relevant, but skip if not in a git repo
      if git rev-parse --is-inside-work-tree &>/dev/null; then
        return 0
      fi
      return 1
      ;;

    env-summary|project-summary)
      # Always relevant
      return 0
      ;;

    *)
      # Unknown loader — assume relevant
      return 0
      ;;
  esac
}

# ─── Estimated Token Sizes (without running the loader) ──────
# estimate_loader_tokens <loader_name>
# Returns approximate token count for the loader's output
estimate_loader_tokens() {
  local loader_name="${1:-}"

  # Input validation
  if [ -z "$loader_name" ]; then
    echo "100"
    return
  fi

  case "$loader_name" in
    env-summary)
      echo "150"
      ;;
    git-context)
      # Depends on dirty state
      if git rev-parse --is-inside-work-tree &>/dev/null; then
        local staged unstaged
        staged=$(git diff --cached --name-only 2>/dev/null | wc -l 2>/dev/null | tr -d ' ' || echo "0")
        unstaged=$(git diff --name-only 2>/dev/null | wc -l 2>/dev/null | tr -d ' ' || echo "0")
        # Validate numeric values
        if ! [[ "$staged" =~ ^[0-9]+$ ]]; then staged=0; fi
        if ! [[ "$unstaged" =~ ^[0-9]+$ ]]; then unstaged=0; fi
        local base=100
        local file_tokens=$(( (staged + unstaged) * 20 ))
        echo $((base + file_tokens))
      else
        echo "30"
      fi
      ;;
    test-status)
      echo "80"
      ;;
    docker-status)
      if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
        local count
        count=$(docker ps -q 2>/dev/null | wc -l 2>/dev/null | tr -d ' ' || echo "0")
        # Validate numeric value
        if ! [[ "$count" =~ ^[0-9]+$ ]]; then count=0; fi
        echo $(( 50 + count * 30 ))
      else
        echo "20"
      fi
      ;;
    api-health)
      echo "100"
      ;;
    deps-audit)
      echo "120"
      ;;
    project-summary)
      echo "200"
      ;;
    *)
      echo "100"
      ;;
  esac
}

# ─── Output Formatting ──────────────────────────────────────
# format_loader_output <loader_name> <raw_output>
# Cleans and structures loader output for Claude-friendly consumption
format_loader_output() {
  local loader_name="${1:-}"
  local raw_output="${2:-}"

  # Input validation
  if [ -z "$loader_name" ]; then
    return
  fi

  # Skip empty output
  if [ -z "$raw_output" ] || [ "$(echo "$raw_output" | tr -d '[:space:]')" = "" ]; then
    return
  fi

  case "$loader_name" in
    git-context)
      # Add relevance tags based on dirty state
      local has_staged=false
      local has_conflicts=false
      if echo "$raw_output" | grep -q "staged: [1-9]"; then
        has_staged=true
      fi
      if echo "$raw_output" | grep -q "CONFLICTS"; then
        has_conflicts=true
      fi

      if [ "$has_conflicts" = "true" ]; then
        echo "<!-- relevance: critical — merge conflicts detected -->"
      elif [ "$has_staged" = "true" ]; then
        echo "<!-- relevance: high — staged changes ready for commit -->"
      fi
      echo "$raw_output"
      ;;

    docker-status)
      # Only output if docker is actually running with containers
      if echo "$raw_output" | grep -q "not installed\|not running"; then
        return
      fi
      echo "$raw_output"
      ;;

    api-health)
      # Filter out DOWN/000 failures, only show useful results
      local filtered=""
      local has_up=false
      while IFS= read -r line; do
        # Keep headers and UP entries
        if echo "$line" | grep -qE '(=== API|--- |✓|UP)'; then
          filtered+="$line"$'\n'
          has_up=true
        elif echo "$line" | grep -qE '(=== END)'; then
          filtered+="$line"$'\n'
        elif echo "$line" | grep -q "no services detected"; then
          return
        fi
      done <<< "$raw_output"
      if [ "$has_up" = "true" ]; then
        printf '%s' "$filtered"
      fi
      ;;

    test-status)
      # Only output if test framework detected
      if echo "$raw_output" | grep -q "no test framework detected"; then
        return
      fi
      echo "$raw_output"
      ;;

    *)
      # Pass through unchanged
      echo "$raw_output"
      ;;
  esac
}

# ─── Predict Relevant Loaders from User Message ─────────────
# predict_relevant_loaders <user_message>
# Returns space-separated list of loader names most relevant to the query
predict_relevant_loaders() {
  local message="${1:-}"
  local loaders=""

  # Git is almost always relevant
  loaders="git-context"

  # Project context is frequently useful
  loaders="$loaders project-summary"

  # Pattern-match user message for specific loader relevance
  if echo "$message" | grep -qiE '(test|spec|coverage|failing|pass|assert)'; then
    loaders="$loaders test-status"
  fi

  if echo "$message" | grep -qiE '(docker|container|compose|image|service)'; then
    loaders="$loaders docker-status"
  fi

  if echo "$message" | grep -qiE '(api|endpoint|health|server|port|curl|fetch|request)'; then
    loaders="$loaders api-health"
  fi

  if echo "$message" | grep -qiE '(depend|package|npm|pip|cargo|install|upgrade|vulnerab|audit)'; then
    loaders="$loaders deps-audit"
  fi

  if echo "$message" | grep -qiE '(env|environment|runtime|shell|node|python|version)'; then
    loaders="$loaders env-summary"
  fi

  # If no specific match, include env-summary as a baseline
  if [ "$loaders" = "git-context project-summary" ]; then
    loaders="$loaders env-summary"
  fi

  echo "$loaders"
}

# ─── Run Relevant Loaders Only ───────────────────────────────
# run_relevant_loaders [user_message]
# Runs only loaders that are both relevant and detected as useful
run_relevant_loaders() {
  local message="${1:-}"
  local predicted
  predicted=$(predict_relevant_loaders "$message")

  for loader in $predicted; do
    if is_loader_relevant "$loader"; then
      local loader_path="$LOADERS_DIR/${loader}.sh"
      if [ -f "$loader_path" ]; then
        local raw_output
        raw_output=$("$loader_path" 2>/dev/null) || true
        format_loader_output "$loader" "$raw_output"
      fi
    fi
  done
}

# ─── Total Token Estimate for Loader Set ────────────────────
# estimate_total_loader_tokens <loader1> <loader2> ...
estimate_total_loader_tokens() {
  local total=0
  for loader in "$@"; do
    if [ -z "$loader" ]; then
      continue
    fi
    if is_loader_relevant "$loader"; then
      local tokens
      tokens=$(estimate_loader_tokens "$loader")
      # Validate numeric value
      if ! [[ "$tokens" =~ ^[0-9]+$ ]]; then
        tokens=100
      fi
      total=$((total + tokens))
    fi
  done
  echo "$total"
}

# ─── CLI Interface ───────────────────────────────────────────
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-help}" in
    relevant)
      # Check if a specific loader is relevant
      if [ -n "${2:-}" ]; then
        if is_loader_relevant "$2"; then
          echo "relevant"
        else
          echo "skipped"
        fi
      else
        echo "Usage: loader-intelligence.sh relevant <loader_name>" >&2
        exit 1
      fi
      ;;
    estimate)
      # Estimate tokens for a loader
      if [ -n "${2:-}" ]; then
        estimate_loader_tokens "$2"
      else
        echo "Usage: loader-intelligence.sh estimate <loader_name>" >&2
        exit 1
      fi
      ;;
    predict)
      # Predict relevant loaders from user message
      shift
      predict_relevant_loaders "$*"
      ;;
    run)
      # Run relevant loaders
      shift
      run_relevant_loaders "$*"
      ;;
    format)
      # Format loader output
      if [ -n "${2:-}" ]; then
        local_output=$(cat)
        format_loader_output "$2" "$local_output"
      else
        echo "Usage: echo 'output' | loader-intelligence.sh format <loader_name>" >&2
        exit 1
      fi
      ;;
    *)
      echo "Usage: loader-intelligence.sh {relevant|estimate|predict|run|format} [args]" >&2
      echo "  relevant <loader>  — check if loader would produce useful output" >&2
      echo "  estimate <loader>  — estimate token count for loader" >&2
      echo "  predict <message>  — predict relevant loaders for user query" >&2
      echo "  run [message]      — run only relevant loaders" >&2
      echo "  format <loader>    — format loader output (stdin)" >&2
      exit 1
      ;;
  esac
fi
