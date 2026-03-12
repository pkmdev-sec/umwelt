#!/usr/bin/env bash
# bang-framework: Adaptive profile router (Innovation 5: Model-Aware)
# Reads task classification from auto_orchestrator and selects the right bang profile.
# Detects model tier and adjusts profile weight accordingly.
# Usage: bang-adaptive.sh [--minimal] [--model <model>]
# Called by UserPromptSubmit hook AFTER auto_orchestrator.py runs.
set -euo pipefail

BANG_DIR="${BANG_DIR:-$HOME/.claude/bang-framework}"
STATE_FILE="$HOME/.claude/hooks/.acontext_state/delegate_mode.json"

# ─── Parse arguments ───────────────────────────────────────────
MINIMAL=""
MODEL_OVERRIDE=""
PREV_ARG=""
for arg in "$@"; do
  case "$arg" in
    --minimal) MINIMAL="--minimal" ;;
    --model) PREV_ARG="--model" ;;
    *)
      if [ "$PREV_ARG" = "--model" ]; then
        MODEL_OVERRIDE="$arg"
        PREV_ARG=""
      fi
      ;;
  esac
done

# ─── Model Detection (Innovation 5) ───────────────────────────
# Priority: --model flag > CLAUDE_MODEL env > ANTHROPIC_MODEL env > default
detect_model_tier() {
  local model="${MODEL_OVERRIDE:-}"
  [ -z "$model" ] && model="${CLAUDE_MODEL:-}"
  [ -z "$model" ] && model="${ANTHROPIC_MODEL:-}"
  [ -z "$model" ] && model="sonnet"  # safe default

  # Normalize to tier
  case "$model" in
    *opus*|*Opus*)   echo "opus" ;;
    *haiku*|*Haiku*) echo "haiku" ;;
    *sonnet*|*Sonnet*|*) echo "sonnet" ;;
  esac
}

MODEL_TIER=$(detect_model_tier)

# Map model tier to default profile
# opus  → debug (full context worth it, big context window)
# sonnet → dev (balanced)
# haiku → minimal (token-constrained)
model_default_profile() {
  case "$MODEL_TIER" in
    opus)  echo "debug" ;;
    haiku) echo "minimal" ;;
    *)     echo "dev" ;;
  esac
}

# ─── Read task_type ────────────────────────────────────────────
TASK_TYPE="IMPLEMENTATION"  # default
ROUTE_TXT="$HOME/.claude/hooks/.acontext_state/bang_route.txt"
if [ -f "$ROUTE_TXT" ]; then
  TASK_TYPE=$(cat "$ROUTE_TXT" 2>/dev/null || echo "IMPLEMENTATION")
elif [ -f "$STATE_FILE" ]; then
  if command -v jq &>/dev/null; then
    TASK_TYPE=$(jq -r '.task_type // "IMPLEMENTATION"' "$STATE_FILE" 2>/dev/null || echo "IMPLEMENTATION")
  else
    TASK_TYPE=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('task_type','IMPLEMENTATION'))" 2>/dev/null || echo "IMPLEMENTATION")
  fi
fi

# ─── Route to profile (model-aware) ───────────────────────────
run_profile() {
  local profile="$1"
  shift
  "$BANG_DIR/profiles/${profile}.sh" "$@"
}

# For haiku: always use minimal regardless of task type
if [ "$MODEL_TIER" = "haiku" ]; then
  run_profile "minimal"
  exit 0
fi

case "$TASK_TYPE" in
  DEBUG|FOLLOWUP)
    if [ "$MINIMAL" = "--minimal" ]; then
      "$BANG_DIR/loaders/git-context.sh" --minimal
    elif [ "$MODEL_TIER" = "opus" ]; then
      run_profile "debug"
    else
      run_profile "dev"
    fi
    ;;
  REVIEW)
    if [ "$MINIMAL" = "--minimal" ]; then
      "$BANG_DIR/loaders/git-context.sh" --diff
    else
      "$BANG_DIR/profiles/review.sh"
    fi
    ;;
  RESEARCH)
    if [ "$MINIMAL" = "--minimal" ]; then
      "$BANG_DIR/loaders/git-context.sh" --minimal
      "$BANG_DIR/loaders/project-summary.sh" --minimal
    elif [ "$MODEL_TIER" = "opus" ]; then
      run_profile "dev" --full
    else
      run_profile "dev"
    fi
    ;;
  IMPLEMENTATION|REFACTOR|*)
    if [ "$MINIMAL" = "--minimal" ]; then
      "$BANG_DIR/loaders/git-context.sh" --minimal
      "$BANG_DIR/loaders/project-summary.sh" --minimal
    else
      run_profile "$(model_default_profile)"
    fi
    ;;
esac
