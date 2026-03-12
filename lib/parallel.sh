#!/usr/bin/env bash
# bang-framework: Parallel execution engine
# Runs loaders concurrently with ordered output collection
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BANG_DIR="${BANG_DIR:-$HOME/.claude/bang-framework}"

# Source config if not already loaded
if [ "${BANG_CONFIG_LOADED:-0}" != "1" ]; then
  source "$SCRIPT_DIR/config.sh"
fi

# Max parallel jobs (default 4, configurable via BANG_MAX_PARALLEL)
MAX_PARALLEL="${BANG_MAX_PARALLEL:-4}"

# Global cleanup tracker
TEMP_DIRS=()
PARALLEL_PIDS=()

# Cleanup handler - kills running jobs and removes temp directories
cleanup_parallel() {
  # Kill all background jobs
  for pid in "${PARALLEL_PIDS[@]+"${PARALLEL_PIDS[@]}"}"; do
    if kill -0 "$pid" 2>/dev/null; then
      kill -TERM "$pid" 2>/dev/null || true
    fi
  done

  # Wait for jobs to finish with timeout
  local timeout=5
  local elapsed=0
  for pid in "${PARALLEL_PIDS[@]+"${PARALLEL_PIDS[@]}"}"; do
    while kill -0 "$pid" 2>/dev/null && [ $elapsed -lt $timeout ]; do
      sleep 0.1
      elapsed=$((elapsed + 1))
    done
    # Force kill if still alive
    if kill -0 "$pid" 2>/dev/null; then
      kill -9 "$pid" 2>/dev/null || true
    fi
    wait "$pid" 2>/dev/null || true
  done

  # Clean up temp directories
  for tmpdir in "${TEMP_DIRS[@]+"${TEMP_DIRS[@]}"}"; do
    if [ -d "$tmpdir" ]; then
      rm -rf "$tmpdir" 2>/dev/null || true
    fi
  done
}

# ─── Parallel Loader Execution ──────────────────────────────────
# Run multiple loaders in parallel, collect results in order
# Usage: parallel_run "loader1 --flag" "loader2" "loader3 --full"
parallel_run() {
  local loaders=("$@")
  local count=${#loaders[@]}

  if [ "$count" -eq 0 ]; then return 0; fi

  # If parallel disabled or only 1 loader, run sequentially
  if [ "$BANG_PARALLEL" != "1" ] || [ "$count" -eq 1 ]; then
    for entry in "${loaders[@]}"; do
      local loader_name loader_args
      loader_name=$(echo "$entry" | awk '{print $1}')
      loader_args=$(echo "$entry" | awk '{$1=""; print $0}' | sed 's/^ //')
      local loader_path="$BANG_DIR/loaders/${loader_name}.sh"
      if [ -f "$loader_path" ]; then
        "$loader_path" $loader_args
        echo ""
      fi
    done
    return 0
  fi

  # Create temp dir for output collection with unique suffix including parent PID
  local parent_pid=$$
  local tmpdir
  tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/bang-parallel-${parent_pid}-XXXXXXXXXX")
  TEMP_DIRS+=("$tmpdir")

  # Set up signal traps for cleanup
  trap cleanup_parallel EXIT SIGINT SIGTERM

  # Create semaphore directory for job limiting (file-based semaphore)
  local semaphore="$tmpdir/semaphore"
  mkdir -p "$semaphore"

  # Launch each loader in background with concurrency control
  local pids=()
  local idx=0
  local failed_jobs=0

  for entry in "${loaders[@]}"; do
    local loader_name loader_args
    loader_name=$(echo "$entry" | awk '{print $1}')
    loader_args=$(echo "$entry" | awk '{$1=""; print $0}' | sed 's/^ //')
    local loader_path="$BANG_DIR/loaders/${loader_name}.sh"

    # Wait for available slot (file-based semaphore)
    while [ "$(ls -1 "$semaphore" 2>/dev/null | wc -l)" -ge "$MAX_PARALLEL" ]; do
      sleep 0.1
      # Clean up stale semaphore files (processes that no longer exist)
      for sem_file in "$semaphore"/*; do
        if [ -f "$sem_file" ]; then
          sem_pid=$(basename "$sem_file")
          if ! kill -0 "$sem_pid" 2>/dev/null; then
            rm -f "$sem_file"
          fi
        fi
      done
    done

    if [ -f "$loader_path" ]; then
      # Run in background, capture output to uniquely-named temp files
      (
        # Use BASHPID for true subshell PID, fall back to $$ + index for bash 3.x
        local job_pid=${BASHPID:-$$_${idx}}
        local job_idx=$idx

        # Create semaphore file for this job using actual subshell PID
        touch "$semaphore/$job_pid"
        trap "rm -f '$semaphore/$job_pid'" EXIT

        # Create unique temp files for this job with PID and index suffix
        local out_temp err_temp rc_temp
        out_temp=$(mktemp "$tmpdir/job-${job_idx}-${job_pid}.out.XXXXXX")
        err_temp=$(mktemp "$tmpdir/job-${job_idx}-${job_pid}.err.XXXXXX")
        rc_temp=$(mktemp "$tmpdir/job-${job_idx}-${job_pid}.rc.XXXXXX")

        # Execute loader and capture output
        local exit_code=0
        "$loader_path" $loader_args > "$out_temp" 2>"$err_temp" || exit_code=$?
        echo "$exit_code" > "$rc_temp"

        # Rename to final output files for sequential collection
        # Use fixed names based on job index for deterministic ordering
        mv "$out_temp" "$tmpdir/${job_idx}_${loader_name}.out"
        mv "$err_temp" "$tmpdir/${job_idx}_${loader_name}.err"
        mv "$rc_temp" "$tmpdir/${job_idx}_${loader_name}.rc"

        # Remove semaphore file
        rm -f "$semaphore/$job_pid"
      ) &

      local bg_pid=$!
      pids+=($bg_pid)
      PARALLEL_PIDS+=($bg_pid)
    else
      # Missing loader - create error files directly
      echo "Warning: loader '$loader_name' not found" > "$tmpdir/${idx}_${loader_name}.err"
      echo "1" > "$tmpdir/${idx}_${loader_name}.rc"
      touch "$tmpdir/${idx}_${loader_name}.out"
    fi
    idx=$((idx + 1))
  done

  # Wait for all jobs to complete
  for pid in "${pids[@]}"; do
    wait "$pid" 2>/dev/null || true
  done

  # Clear parallel PIDs tracker
  PARALLEL_PIDS=()

  # Collect results in original order and track failures
  for i in $(seq 0 $((count - 1))); do
    # Output stdout (find by index prefix for deterministic ordering)
    local out_file
    out_file=$(find "$tmpdir" -name "${i}_*.out" 2>/dev/null | head -1)
    if [ -f "$out_file" ]; then
      cat "$out_file"
      echo ""
    fi

    # Output stderr
    local err_file
    err_file=$(find "$tmpdir" -name "${i}_*.err" 2>/dev/null | head -1)
    if [ -f "$err_file" ] && [ -s "$err_file" ]; then
      cat "$err_file" >&2
    fi

    # Track exit codes
    local rc_file
    rc_file=$(find "$tmpdir" -name "${i}_*.rc" 2>/dev/null | head -1)
    if [ -f "$rc_file" ]; then
      local rc
      rc=$(cat "$rc_file")
      if [ "$rc" -ne 0 ]; then
        failed_jobs=$((failed_jobs + 1))
      fi
    fi
  done

  # Cleanup temp directory
  rm -rf "$tmpdir"

  # Return aggregate exit code
  if [ "$failed_jobs" -gt 0 ]; then
    return 1
  fi
  return 0
}

# ─── Parallel Profile Helper ───────────────────────────────────
# Helper specifically for profiles: runs groups of loaders
# Groups execute in order, loaders within a group run in parallel
# Usage: parallel_profile "group1_loader1 group1_loader2" "group2_loader1"
parallel_profile() {
  local groups=("$@")
  for group in "${groups[@]}"; do
    local loaders_in_group=()
    for loader_spec in $group; do
      loaders_in_group+=("$loader_spec")
    done
    parallel_run "${loaders_in_group[@]}"
  done
}
