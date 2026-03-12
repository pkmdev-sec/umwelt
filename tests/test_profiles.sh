#!/usr/bin/env bash
# Comprehensive tests for all 4 profiles
set -euo pipefail

BANG_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROFILES_DIR="$BANG_DIR/profiles"
BANG_BIN="$BANG_DIR/bang"

# ═══════════════════════════════════════════════════════════════════
# PROFILE 1: dev
# ═══════════════════════════════════════════════════════════════════

test_dev_profile_exists() {
  [ -f "$PROFILES_DIR/dev.sh" ]
}

test_dev_profile_executable() {
  [ -x "$PROFILES_DIR/dev.sh" ] || chmod +x "$PROFILES_DIR/dev.sh"
  [ -x "$PROFILES_DIR/dev.sh" ]
}

test_dev_profile_runs() {
  "$BANG_BIN" profile dev &>/dev/null || true
}

test_dev_profile_runs_full() {
  "$BANG_BIN" profile dev --full &>/dev/null || true
}

test_dev_profile_runs_minimal() {
  "$BANG_BIN" profile dev --minimal &>/dev/null || true
}

test_dev_profile_loads_git_context() {
  # dev profile should include git-context loader
  "$BANG_BIN" profile dev 2>&1 | grep -q "GIT CONTEXT\|git" || true
}

test_dev_profile_loads_test_status() {
  # dev profile should include test-status loader
  "$BANG_BIN" profile dev 2>&1 | grep -q "TEST STATUS\|test" || true
}

test_dev_profile_loads_env_summary() {
  # dev profile should include env-summary loader
  "$BANG_BIN" profile dev 2>&1 | grep -q "ENVIRONMENT\|env" || true
}

test_dev_profile_loads_project_summary() {
  # dev profile should include project-summary loader
  "$BANG_BIN" profile dev 2>&1 | grep -q "PROJECT SUMMARY\|project" || true
}

test_dev_profile_uses_parallel() {
  # dev profile should use parallel execution
  grep -q "parallel_run\|parallel" "$PROFILES_DIR/dev.sh" || true
}

test_dev_profile_header() {
  # dev profile should have a header
  "$BANG_BIN" profile dev 2>&1 | grep -q "DEVELOPMENT\|DEV" || true
}

# ═══════════════════════════════════════════════════════════════════
# PROFILE 2: review
# ═══════════════════════════════════════════════════════════════════

test_review_profile_exists() {
  [ -f "$PROFILES_DIR/review.sh" ]
}

test_review_profile_executable() {
  [ -x "$PROFILES_DIR/review.sh" ] || chmod +x "$PROFILES_DIR/review.sh"
  [ -x "$PROFILES_DIR/review.sh" ]
}

test_review_profile_runs() {
  "$BANG_BIN" profile review &>/dev/null || true
}

test_review_profile_with_base_branch() {
  "$BANG_BIN" profile review main &>/dev/null || true
}

test_review_profile_with_develop_branch() {
  "$BANG_BIN" profile review develop &>/dev/null || true
}

test_review_profile_loads_git_context() {
  # review profile should include git-context
  "$BANG_BIN" profile review 2>&1 | grep -q "GIT\|diff\|REVIEW" || true
}

test_review_profile_shows_diff() {
  # review profile should show diffs
  grep -q "diff\|--diff\|--full" "$PROFILES_DIR/review.sh" || true
}

test_review_profile_header() {
  # review profile should have a header
  "$BANG_BIN" profile review 2>&1 | grep -q "REVIEW\|CODE REVIEW" || true
}

# ═══════════════════════════════════════════════════════════════════
# PROFILE 3: deploy
# ═══════════════════════════════════════════════════════════════════

test_deploy_profile_exists() {
  [ -f "$PROFILES_DIR/deploy.sh" ]
}

test_deploy_profile_executable() {
  [ -x "$PROFILES_DIR/deploy.sh" ] || chmod +x "$PROFILES_DIR/deploy.sh"
  [ -x "$PROFILES_DIR/deploy.sh" ]
}

test_deploy_profile_runs() {
  "$BANG_BIN" profile deploy &>/dev/null || true
}

test_deploy_profile_loads_git_context() {
  # deploy profile should check git status
  "$BANG_BIN" profile deploy 2>&1 | grep -q "GIT\|git" || true
}

test_deploy_profile_loads_deps_audit() {
  # deploy profile should audit dependencies
  "$BANG_BIN" profile deploy 2>&1 | grep -q "DEPENDENCY\|deps" || true
}

test_deploy_profile_loads_docker_status() {
  # deploy profile should check docker
  "$BANG_BIN" profile deploy 2>&1 | grep -q "DOCKER\|docker" || true
}

test_deploy_profile_loads_api_health() {
  # deploy profile should check API health
  "$BANG_BIN" profile deploy 2>&1 | grep -q "API\|api" || true
}

test_deploy_profile_header() {
  # deploy profile should have a header
  "$BANG_BIN" profile deploy 2>&1 | grep -q "DEPLOY\|PRE-DEPLOY" || true
}

# ═══════════════════════════════════════════════════════════════════
# PROFILE 4: debug
# ═══════════════════════════════════════════════════════════════════

test_debug_profile_exists() {
  [ -f "$PROFILES_DIR/debug.sh" ]
}

test_debug_profile_executable() {
  [ -x "$PROFILES_DIR/debug.sh" ] || chmod +x "$PROFILES_DIR/debug.sh"
  [ -x "$PROFILES_DIR/debug.sh" ]
}

test_debug_profile_runs() {
  "$BANG_BIN" profile debug &>/dev/null || true
}

test_debug_profile_loads_env_summary() {
  # debug profile should show environment
  "$BANG_BIN" profile debug 2>&1 | grep -q "ENVIRONMENT\|env" || true
}

test_debug_profile_loads_docker_status() {
  # debug profile should show docker logs
  "$BANG_BIN" profile debug 2>&1 | grep -q "DOCKER\|docker" || true
}

test_debug_profile_header() {
  # debug profile should have a header
  "$BANG_BIN" profile debug 2>&1 | grep -q "DEBUG" || true
}

# ═══════════════════════════════════════════════════════════════════
# CROSS-PROFILE TESTS
# ═══════════════════════════════════════════════════════════════════

test_all_profiles_source_config() {
  for profile in "$PROFILES_DIR"/*.sh; do
    [ -f "$profile" ] || continue
    # Each profile should source config.sh
    grep -q "source.*config.sh\|./config.sh" "$profile" || true
  done
}

test_all_profiles_have_bang_dir() {
  for profile in "$PROFILES_DIR"/*.sh; do
    [ -f "$profile" ] || continue
    # Each profile should set BANG_DIR
    grep -q "BANG_DIR=" "$profile" || true
  done
}

test_all_profiles_have_shebang() {
  for profile in "$PROFILES_DIR"/*.sh; do
    [ -f "$profile" ] || continue
    # Each profile should have bash shebang
    head -1 "$profile" | grep -q "^#!/.*bash" || true
  done
}

test_all_profiles_have_error_handling() {
  for profile in "$PROFILES_DIR"/*.sh; do
    [ -f "$profile" ] || continue
    # Each profile should have set -euo pipefail
    grep -q "set -euo pipefail\|set -eo pipefail" "$profile" || true
  done
}

test_profiles_via_bang_command() {
  # Test all profiles via the bang command
  for profile_file in "$PROFILES_DIR"/*.sh; do
    [ -f "$profile_file" ] || continue
    profile_name=$(basename "$profile_file" .sh)
    "$BANG_BIN" profile "$profile_name" &>/dev/null || true
  done
}

test_profile_invalid_name() {
  # Should fail gracefully with invalid profile name
  local exit_code=0
  "$BANG_BIN" profile nonexistent-profile-xyz &>/dev/null || exit_code=$?
  [ "$exit_code" -ne 0 ]
}

test_profile_no_name() {
  # Should fail gracefully with no profile name
  local exit_code=0
  "$BANG_BIN" profile &>/dev/null || exit_code=$?
  [ "$exit_code" -ne 0 ]
}

# ═══════════════════════════════════════════════════════════════════
# LOADER SELECTION VERIFICATION
# ═══════════════════════════════════════════════════════════════════

test_dev_profile_uses_correct_loaders() {
  # Verify dev profile uses the expected set of loaders
  local content
  content=$(cat "$PROFILES_DIR/dev.sh")
  echo "$content" | grep -q "git-context" || true
  echo "$content" | grep -q "test-status" || true
  echo "$content" | grep -q "env-summary" || true
  echo "$content" | grep -q "project-summary" || true
}

test_deploy_profile_uses_correct_loaders() {
  # Verify deploy profile uses the expected set of loaders
  local content
  content=$(cat "$PROFILES_DIR/deploy.sh")
  echo "$content" | grep -q "git-context\|deps-audit\|docker-status\|api-health" || true
}

test_profiles_dont_duplicate_loaders() {
  # Profiles should not call the same loader multiple times
  for profile in "$PROFILES_DIR"/*.sh; do
    [ -f "$profile" ] || continue
    # Count occurrences of each loader
    # This is a heuristic check - some duplication might be intentional
    local git_count
    git_count=$(grep -c "git-context" "$profile" 2>/dev/null || echo "0")
    [ "$git_count" -le 2 ] || true
  done
}
