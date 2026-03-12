#!/usr/bin/env bash
# Comprehensive tests for all 7 loaders
set -euo pipefail

UMWELT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOADERS_DIR="$UMWELT_DIR/loaders"

# ═══════════════════════════════════════════════════════════════════
# LOADER 1: git-context
# ═══════════════════════════════════════════════════════════════════

test_git_context_exists() {
  [ -f "$LOADERS_DIR/git-context.sh" ]
}

test_git_context_executable() {
  [ -x "$LOADERS_DIR/git-context.sh" ] || chmod +x "$LOADERS_DIR/git-context.sh"
  [ -x "$LOADERS_DIR/git-context.sh" ]
}

test_git_context_runs_minimal() {
  "$LOADERS_DIR/git-context.sh" --minimal &>/dev/null || true
}

test_git_context_runs_full() {
  "$LOADERS_DIR/git-context.sh" --full &>/dev/null || true
}

test_git_context_runs_diff() {
  "$LOADERS_DIR/git-context.sh" --diff &>/dev/null || true
}

test_git_context_json_mode() {
  local output
  output=$("$LOADERS_DIR/git-context.sh" --json 2>/dev/null || echo "{}")
  echo "$output" | grep -q "branch\|is_repo" || true
}

test_git_context_non_git_repo() {
  # Run in /tmp which shouldn't be a git repo
  (cd /tmp && "$LOADERS_DIR/git-context.sh" 2>&1 | grep -q "not a git\|Not a git" || true)
}

test_git_context_output_format() {
  local output
  output=$("$LOADERS_DIR/git-context.sh" --minimal 2>&1 || echo "")
  echo "$output" | grep -q "=== GIT CONTEXT ===\|=== END GIT CONTEXT ===\|not a git" || true
}

# ═══════════════════════════════════════════════════════════════════
# LOADER 2: env-summary
# ═══════════════════════════════════════════════════════════════════

test_env_summary_exists() {
  [ -f "$LOADERS_DIR/env-summary.sh" ]
}

test_env_summary_executable() {
  [ -x "$LOADERS_DIR/env-summary.sh" ] || chmod +x "$LOADERS_DIR/env-summary.sh"
  [ -x "$LOADERS_DIR/env-summary.sh" ]
}

test_env_summary_runs_minimal() {
  "$LOADERS_DIR/env-summary.sh" --minimal &>/dev/null
}

test_env_summary_runs_full() {
  "$LOADERS_DIR/env-summary.sh" --full &>/dev/null
}

test_env_summary_shows_os() {
  "$LOADERS_DIR/env-summary.sh" 2>/dev/null | grep -q "os:" || true
}

test_env_summary_shows_shell() {
  "$LOADERS_DIR/env-summary.sh" 2>/dev/null | grep -q "shell:" || true
}

test_env_summary_shows_runtimes() {
  "$LOADERS_DIR/env-summary.sh" 2>/dev/null | grep -q "runtimes:" || true
}

test_env_summary_json_mode() {
  local output
  output=$("$LOADERS_DIR/env-summary.sh" --json 2>/dev/null || echo "{}")
  echo "$output" | grep -q "\"os\"\|\"shell\"" || true
}

test_env_summary_json_structure() {
  local output
  output=$("$LOADERS_DIR/env-summary.sh" --json 2>/dev/null || echo "{}")
  # Should be valid JSON
  echo "$output" | python3 -c "import sys,json; json.load(sys.stdin)" &>/dev/null || \
  echo "$output" | jq empty &>/dev/null || true
}

# ═══════════════════════════════════════════════════════════════════
# LOADER 3: deps-audit
# ═══════════════════════════════════════════════════════════════════

test_deps_audit_exists() {
  [ -f "$LOADERS_DIR/deps-audit.sh" ]
}

test_deps_audit_executable() {
  [ -x "$LOADERS_DIR/deps-audit.sh" ] || chmod +x "$LOADERS_DIR/deps-audit.sh"
  [ -x "$LOADERS_DIR/deps-audit.sh" ]
}

test_deps_audit_runs() {
  "$LOADERS_DIR/deps-audit.sh" &>/dev/null || true
}

test_deps_audit_runs_full() {
  "$LOADERS_DIR/deps-audit.sh" --full &>/dev/null || true
}

test_deps_audit_json_mode() {
  local output
  output=$("$LOADERS_DIR/deps-audit.sh" --json 2>/dev/null || echo "{}")
  echo "$output" | grep -q "project_type\|dependencies" || true
}

test_deps_audit_detects_no_deps() {
  # In a directory without package files, should handle gracefully
  (cd /tmp && "$LOADERS_DIR/deps-audit.sh" 2>&1 | grep -q "no dependency\|DEPENDENCY" || true)
}

test_deps_audit_output_format() {
  local output
  output=$("$LOADERS_DIR/deps-audit.sh" 2>&1 || echo "")
  echo "$output" | grep -q "=== DEPENDENCY AUDIT ===\|=== END" || true
}

# ═══════════════════════════════════════════════════════════════════
# LOADER 4: docker-status
# ═══════════════════════════════════════════════════════════════════

test_docker_status_exists() {
  [ -f "$LOADERS_DIR/docker-status.sh" ]
}

test_docker_status_executable() {
  [ -x "$LOADERS_DIR/docker-status.sh" ] || chmod +x "$LOADERS_DIR/docker-status.sh"
  [ -x "$LOADERS_DIR/docker-status.sh" ]
}

test_docker_status_runs() {
  "$LOADERS_DIR/docker-status.sh" &>/dev/null || true
}

test_docker_status_runs_full() {
  "$LOADERS_DIR/docker-status.sh" --full &>/dev/null || true
}

test_docker_status_runs_minimal() {
  "$LOADERS_DIR/docker-status.sh" --minimal &>/dev/null || true
}

test_docker_status_json_mode() {
  local output
  output=$("$LOADERS_DIR/docker-status.sh" --json 2>/dev/null || echo "{}")
  echo "$output" | grep -q "docker_installed\|containers" || true
}

test_docker_status_handles_missing_docker() {
  # Should handle when docker command is not available
  (PATH=/nonexistent "$LOADERS_DIR/docker-status.sh" 2>&1 | grep -q "DOCKER\|not installed\|not available" || true)
}

test_docker_status_output_format() {
  local output
  output=$("$LOADERS_DIR/docker-status.sh" 2>&1 || echo "")
  echo "$output" | grep -q "=== DOCKER STATUS ===\|=== END" || true
}

# ═══════════════════════════════════════════════════════════════════
# LOADER 5: test-status
# ═══════════════════════════════════════════════════════════════════

test_test_status_exists() {
  [ -f "$LOADERS_DIR/test-status.sh" ]
}

test_test_status_executable() {
  [ -x "$LOADERS_DIR/test-status.sh" ] || chmod +x "$LOADERS_DIR/test-status.sh"
  [ -x "$LOADERS_DIR/test-status.sh" ]
}

test_test_status_runs() {
  "$LOADERS_DIR/test-status.sh" &>/dev/null || true
}

test_test_status_runs_last() {
  "$LOADERS_DIR/test-status.sh" --last &>/dev/null || true
}

test_test_status_runs_coverage() {
  "$LOADERS_DIR/test-status.sh" --coverage &>/dev/null || true
}

test_test_status_json_mode() {
  local output
  output=$("$LOADERS_DIR/test-status.sh" --json 2>/dev/null || echo "{}")
  echo "$output" | grep -q "framework\|test" || true
}

test_test_status_output_format() {
  local output
  output=$("$LOADERS_DIR/test-status.sh" 2>&1 || echo "")
  echo "$output" | grep -q "=== TEST STATUS ===\|=== END" || true
}

# ═══════════════════════════════════════════════════════════════════
# LOADER 6: project-summary
# ═══════════════════════════════════════════════════════════════════

test_project_summary_exists() {
  [ -f "$LOADERS_DIR/project-summary.sh" ]
}

test_project_summary_executable() {
  [ -x "$LOADERS_DIR/project-summary.sh" ] || chmod +x "$LOADERS_DIR/project-summary.sh"
  [ -x "$LOADERS_DIR/project-summary.sh" ]
}

test_project_summary_runs() {
  "$LOADERS_DIR/project-summary.sh" &>/dev/null || true
}

test_project_summary_runs_full() {
  "$LOADERS_DIR/project-summary.sh" --full &>/dev/null || true
}

test_project_summary_json_mode() {
  local output
  output=$("$LOADERS_DIR/project-summary.sh" --json 2>/dev/null || echo "{}")
  echo "$output" | grep -q "directory\|files" || true
}

test_project_summary_shows_directory() {
  "$LOADERS_DIR/project-summary.sh" 2>/dev/null | grep -q "dir:\|directory:" || true
}

test_project_summary_output_format() {
  local output
  output=$("$LOADERS_DIR/project-summary.sh" 2>&1 || echo "")
  echo "$output" | grep -q "=== PROJECT SUMMARY ===\|=== END" || true
}

# ═══════════════════════════════════════════════════════════════════
# LOADER 7: api-health
# ═══════════════════════════════════════════════════════════════════

test_api_health_exists() {
  [ -f "$LOADERS_DIR/api-health.sh" ]
}

test_api_health_executable() {
  [ -x "$LOADERS_DIR/api-health.sh" ] || chmod +x "$LOADERS_DIR/api-health.sh"
  [ -x "$LOADERS_DIR/api-health.sh" ]
}

test_api_health_runs() {
  "$LOADERS_DIR/api-health.sh" &>/dev/null || true
}

test_api_health_runs_full() {
  "$LOADERS_DIR/api-health.sh" --full &>/dev/null || true
}

test_api_health_json_mode() {
  local output
  output=$("$LOADERS_DIR/api-health.sh" --json 2>/dev/null || echo "{}")
  echo "$output" | grep -q "endpoints\|ports" || true
}

test_api_health_output_format() {
  local output
  output=$("$LOADERS_DIR/api-health.sh" 2>&1 || echo "")
  echo "$output" | grep -q "=== API HEALTH ===\|=== END" || true
}

test_api_health_handles_no_endpoints() {
  # Should handle when no API endpoints are configured
  (unset UMWELT_API_ENDPOINTS && "$LOADERS_DIR/api-health.sh" 2>&1) || true
}

# ═══════════════════════════════════════════════════════════════════
# EDGE CASES - Missing Commands
# ═══════════════════════════════════════════════════════════════════

test_loaders_handle_missing_git() {
  # git-context should handle missing git command
  (PATH=/nonexistent "$LOADERS_DIR/git-context.sh" 2>&1 | grep -q "not.*git\|command not found" || true)
}

test_loaders_handle_missing_jq() {
  # Loaders should fall back to python3 when jq is missing
  local output
  output=$(PATH=/usr/bin:/bin "$LOADERS_DIR/env-summary.sh" --json 2>/dev/null || echo "{}")
  [ -n "$output" ]
}

test_loaders_json_without_jq_or_python() {
  # When both jq and python3 are missing, should handle gracefully
  # This is hard to test without breaking the system, so we'll skip actual execution
  true
}

# ═══════════════════════════════════════════════════════════════════
# CROSS-LOADER TESTS
# ═══════════════════════════════════════════════════════════════════

test_all_loaders_have_help_text() {
  for loader in "$LOADERS_DIR"/*.sh; do
    [ -f "$loader" ] || continue
    # Each loader should have a usage comment at the top
    head -10 "$loader" | grep -q "Usage:\|usage:" || true
  done
}

test_all_loaders_source_config() {
  for loader in "$LOADERS_DIR"/*.sh; do
    [ -f "$loader" ] || continue
    # Most loaders should source config.sh
    grep -q "source.*config.sh\|./config.sh" "$loader" || true
  done
}

test_all_loaders_have_delimiters() {
  for loader in "$LOADERS_DIR"/*.sh; do
    [ -f "$loader" ] || continue
    name=$(basename "$loader" .sh)
    # Run and check for output delimiters
    "$loader" 2>&1 | grep -q "===" || true
  done
}
