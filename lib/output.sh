#!/usr/bin/env bash
# ============================================================================
# output.sh — Centralized output formatting
# ============================================================================
# Purpose: Provides unified text and JSON rendering functions for all loaders.
#          Includes cache-split section markers, format detection, and jq/
#          python3 fallback for JSON operations.
#
# Usage: source lib/output.sh
#        Text functions: text_header, text_kv, text_check, text_item
#        JSON functions: json_escape, json_build_object, json_get, json_array
#        Cache markers: text_stable_header/footer, text_volatile_header/footer
#
# Dependencies: bash 3.2+, jq (optional, falls back to python3)
#
# Output: Formatted text or JSON depending on $UMWELT_OUTPUT_FORMAT or --json
#         flag. Helpers for structured context with proper section delimiters.
# ============================================================================
set -euo pipefail

# Check for jq availability
HAS_JQ=false
if command -v jq &>/dev/null; then
  HAS_JQ=true
fi

# ═══════════════════════════════════════════════════════════════════
# TEXT OUTPUT FUNCTIONS
# ═══════════════════════════════════════════════════════════════════

# Render section header
# Usage: text_header "SECTION NAME"
text_header() {
  local title="$1"
  echo "=== $title ==="
}

# Render section footer
# Usage: text_footer "SECTION NAME"
text_footer() {
  local title="$1"
  echo "=== END $title ==="
}

# Render subsection header
# Usage: text_subsection "subsection name"
text_subsection() {
  local title="$1"
  echo ""
  echo "--- $title ---"
}

# Render key-value pair
# Usage: text_kv "key" "value"
text_kv() {
  local key="$1"
  local value="$2"
  echo "${key}: ${value}"
}

# Render indented key-value pair
# Usage: text_kv_indent "key" "value" [indent_level]
text_kv_indent() {
  local key="$1"
  local value="$2"
  local indent="${3:-  }"
  echo "${indent}${key}: ${value}"
}

# Render list item
# Usage: text_item "content" [prefix]
text_item() {
  local content="$1"
  local prefix="${2:-  }"
  echo "${prefix}${content}"
}

# Render checkmark item
# Usage: text_check "content" [status]
text_check() {
  local content="$1"
  local status="${2:-ok}"
  if [ "$status" = "ok" ] || [ "$status" = "up" ]; then
    echo "  ✓ ${content}"
  else
    echo "  ✗ ${content}"
  fi
}

# ═══════════════════════════════════════════════════════════════════
# JSON OUTPUT FUNCTIONS
# ═══════════════════════════════════════════════════════════════════

# Escape string for JSON (using jq or python3)
# Usage: value=$(json_escape "string value")
json_escape() {
  local value="$1"
  if [ "$HAS_JQ" = "true" ]; then
    echo "$value" | jq -R -s '.'
  else
    python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))" <<< "$value" 2>/dev/null || echo "\"$value\""
  fi
}

# Build JSON object from associative array (bash 4+)
# Usage: json_build_object "key1" "val1" "key2" "val2" ...
# For null values, pass empty string and handle in jq
json_build_object() {
  local args=("$@")
  local arg_count=${#args[@]}

  if [ "$HAS_JQ" = "true" ]; then
    # Build jq arguments
    local jq_args=()
    local jq_obj="{"
    local first=true

    for ((i=0; i<arg_count; i+=2)); do
      local key="${args[i]}"
      local val="${args[i+1]}"

      [ "$first" = false ] && jq_obj+=","
      jq_obj+="\"$key\":\$$key"
      jq_args+=("--arg" "$key" "$val")
      first=false
    done
    jq_obj+="}"

    jq -n "${jq_args[@]}" "$jq_obj" 2>/dev/null || echo '{}'
  else
    # Python fallback
    local py_dict="{"
    local first=true
    for ((i=0; i<arg_count; i+=2)); do
      local key="${args[i]}"
      local val="${args[i+1]}"

      [ "$first" = false ] && py_dict+=","
      py_dict+="'$key':'$val'"
      first=false
    done
    py_dict+="}"

    python3 -c "import json; print(json.dumps($py_dict))" 2>/dev/null || echo '{}'
  fi
}

# Build simple JSON object with explicit types
# Usage: json_object <<EOF
# string:key:value
# number:count:42
# bool:enabled:true
# null:optional:
# EOF
json_object() {
  if [ "$HAS_JQ" = "true" ]; then
    local jq_args=()
    local jq_expr="{"
    local first=true

    while IFS=: read -r type key value; do
      [ -z "$key" ] && continue

      [ "$first" = false ] && jq_expr+=","
      case "$type" in
        string)
          jq_args+=("--arg" "$key" "$value")
          jq_expr+="\"$key\":\$$key"
          ;;
        number)
          jq_args+=("--argjson" "$key" "${value:-0}")
          jq_expr+="\"$key\":\$$key"
          ;;
        bool)
          jq_args+=("--argjson" "$key" "$value")
          jq_expr+="\"$key\":\$$key"
          ;;
        null)
          jq_expr+="\"$key\":null"
          ;;
      esac
      first=false
    done

    jq_expr+="}"
    jq -n "${jq_args[@]}" "$jq_expr" 2>/dev/null || echo '{}'
  else
    # Python fallback
    local py_items=()
    while IFS=: read -r type key value; do
      [ -z "$key" ] && continue

      case "$type" in
        string)
          py_items+=("'$key':\"$value\"")
          ;;
        number)
          py_items+=("'$key':${value:-0}")
          ;;
        bool)
          py_items+=("'$key':$value")
          ;;
        null)
          py_items+=("'$key':None")
          ;;
      esac
    done

    local py_dict="{"
    py_dict+=$(IFS=,; echo "${py_items[*]}")
    py_dict+="}"

    python3 -c "import json; print(json.dumps($py_dict))" 2>/dev/null || echo '{}'
  fi
}

# Check JSON validity
# Usage: if json_valid "$json_string"; then ...
json_valid() {
  local json="$1"
  if [ "$HAS_JQ" = "true" ]; then
    echo "$json" | jq empty 2>/dev/null && return 0
  else
    echo "$json" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null && return 0
  fi
  return 1
}

# Extract value from JSON
# Usage: value=$(json_get "$json" ".key.subkey")
json_get() {
  local json="$1"
  local query="$2"

  if [ "$HAS_JQ" = "true" ]; then
    echo "$json" | jq -r "$query" 2>/dev/null || echo ""
  else
    # Python fallback for simple queries (limited support)
    echo "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
query = '$query'.strip('.')
keys = query.split('.')
result = data
for k in keys:
    if isinstance(result, dict):
        result = result.get(k, '')
    else:
        result = ''
        break
print(result or '')
" 2>/dev/null || echo ""
  fi
}

# Parse JSON file
# Usage: value=$(json_parse_file "file.json" ".key")
json_parse_file() {
  local file="$1"
  local query="${2:-.}"

  if [ ! -f "$file" ]; then
    echo ""
    return 1
  fi

  if [ "$HAS_JQ" = "true" ]; then
    jq -r "$query" "$file" 2>/dev/null || echo ""
  else
    python3 -c "
import json
with open('$file') as f:
    data = json.load(f)
query = '$query'.strip('.')
if query == '':
    print(json.dumps(data))
else:
    keys = query.split('.')
    result = data
    for k in keys:
        if isinstance(result, dict):
            result = result.get(k, '')
        else:
            result = ''
            break
    if isinstance(result, (dict, list)):
        print(json.dumps(result))
    else:
        print(result or '')
" 2>/dev/null || echo ""
  fi
}

# Convert bash array to JSON array
# Usage: json_array "item1" "item2" "item3"
json_array() {
  local items=("$@")

  if [ "$HAS_JQ" = "true" ]; then
    printf '%s\n' "${items[@]}" | jq -R -s 'split("\n") | .[:-1]'
  else
    python3 -c "
import json, sys
items = [line.strip() for line in sys.stdin if line.strip()]
print(json.dumps(items))
" <<< "$(printf '%s\n' "${items[@]}")"
  fi
}

# ═══════════════════════════════════════════════════════════════════
# CACHE-SPLIT OUTPUT MARKERS (Innovation 2)
# ═══════════════════════════════════════════════════════════════════

# Render stable context section header/footer
text_stable_header() {
  echo "=== STABLE CONTEXT ==="
}

text_stable_footer() {
  echo "=== END STABLE CONTEXT ==="
}

# Render volatile context section header/footer
text_volatile_header() {
  local suffix="${1:-}"
  if [ -n "$suffix" ]; then
    echo "=== VOLATILE CONTEXT (${suffix}) ==="
  else
    echo "=== VOLATILE CONTEXT ==="
  fi
}

text_volatile_footer() {
  echo "=== END VOLATILE CONTEXT ==="
}

# ═══════════════════════════════════════════════════════════════════
# FORMAT DETECTION
# ═══════════════════════════════════════════════════════════════════

# Determine output format from args and config
# Usage: OUTPUT_FMT=$(detect_output_format "$@")
detect_output_format() {
  local fmt="${UMWELT_OUTPUT_FORMAT:-text}"
  for arg in "$@"; do
    if [ "$arg" = "--json" ]; then
      fmt="json"
      break
    fi
  done
  echo "$fmt"
}

# Wrapper to output either text or JSON
# Usage: output_format <text_fn> <json_fn> [args...]
output_format() {
  local text_fn="$1"
  local json_fn="$2"
  shift 2

  local fmt=$(detect_output_format "$@")

  if [ "$fmt" = "json" ]; then
    "$json_fn" "$@"
  else
    "$text_fn" "$@"
  fi
}
