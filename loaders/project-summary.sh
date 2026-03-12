#!/usr/bin/env bash
# umwelt: project-summary loader
# High-level project overview — structure, size, tech stack, entry points
# Usage: umwelt project-summary [--full|--json]
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

PROJECT_DIR="${UMWELT_PROJECT_DIR:-.}"
SCAN_DEPTH="${UMWELT_SCAN_DEPTH:-4}"
FILE_EXTENSIONS="${UMWELT_FILE_EXTENSIONS:-ts tsx js jsx py rs go swift java kt rb php css scss html md json yaml yml toml}"
EXCLUDE_DIRS="${UMWELT_EXCLUDE_DIRS:-node_modules .git dist build .next .nuxt target __pycache__ .pytest_cache coverage .mypy_cache Library}"

# Build find exclude pattern
FIND_EXCLUDES=""
for d in $EXCLUDE_DIRS; do
  FIND_EXCLUDES="$FIND_EXCLUDES -not -path '*/${d}/*'"
done

# ─── Gather File Counts ──────────────────────────────────────────
declare -a FILE_COUNTS=()
for ext in $FILE_EXTENSIONS; do
  COUNT=$(eval "find '$PROJECT_DIR' -maxdepth '$SCAN_DEPTH' -name '*.${ext}' $FIND_EXCLUDES 2>/dev/null" | wc -l | tr -d ' ' || echo "0")
  if [ "$COUNT" -gt 0 ] 2>/dev/null; then
    FILE_COUNTS+=("${ext}:${COUNT}")
  fi
done

# ─── LOC Estimate ─────────────────────────────────────────────────
CODE_EXTS="-name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' -o -name '*.py' -o -name '*.rs' -o -name '*.go' -o -name '*.swift'"
TOTAL_LOC=$(eval "find '$PROJECT_DIR' -maxdepth '$SCAN_DEPTH' \\( $CODE_EXTS \\) $FIND_EXCLUDES 2>/dev/null" | head -500 | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}' || echo "0")

# ─── Directory Structure ──────────────────────────────────────────
declare -a TOP_DIRS=()
while IFS= read -r dir; do
  NAME=$(basename "$dir")
  # Skip excluded directories
  skip=false
  for excl in $EXCLUDE_DIRS; do
    if [ "$NAME" = "$excl" ]; then skip=true; break; fi
  done
  if [ "$skip" = "true" ]; then continue; fi
  ITEMS=$(ls -1 "$dir" 2>/dev/null | wc -l | tr -d ' ')
  TOP_DIRS+=("${NAME}:${ITEMS}")
done < <(ls -d "$PROJECT_DIR"/*/ 2>/dev/null | head -20)

# ─── Entry Points ─────────────────────────────────────────────────
declare -a ENTRY_POINTS=()
for f in "src/index.ts" "src/index.tsx" "src/main.ts" "src/main.tsx" "src/app.ts" "src/app.tsx" "index.js" "index.ts" "main.py" "app.py" "main.go" "cmd/main.go" "src/main.rs" "src/lib.rs" "Package.swift"; do
  if [ -f "$PROJECT_DIR/$f" ]; then
    ENTRY_POINTS+=("$f")
  fi
done

# ─── Config Files ─────────────────────────────────────────────────
declare -a CONFIG_FILES=()
for f in "package.json" "tsconfig.json" "vite.config.ts" "next.config.js" "next.config.ts" "webpack.config.js" "rollup.config.js" "pyproject.toml" "Cargo.toml" "go.mod" "Makefile" "Dockerfile" "docker-compose.yml" ".env.example" ".github/workflows" "CLAUDE.md" ".claude/settings.json"; do
  if [ -f "$PROJECT_DIR/$f" ] || [ -d "$PROJECT_DIR/$f" ]; then
    CONFIG_FILES+=("$f")
  fi
done

# ─── NPM Scripts (full mode) ─────────────────────────────────────
NPM_SCRIPTS=""
if [ -f "$PROJECT_DIR/package.json" ] && [ "$MODE" = "--full" ]; then
  if command -v jq &>/dev/null; then
    NPM_SCRIPTS=$(jq -r '.scripts // {} | to_entries | .[] | "\(.key): \(.value | .[0:60])"' "$PROJECT_DIR/package.json" 2>/dev/null || echo "")
  else
    NPM_SCRIPTS=$(python3 -c "
import json
with open('$PROJECT_DIR/package.json') as f:
    d = json.load(f)
for k, v in d.get('scripts', {}).items():
    print(f'{k}: {v[:60]}')
" 2>/dev/null || echo "")
  fi
fi

# ─── README (full mode) ──────────────────────────────────────────
README_EXCERPT=""
if [ -f "$PROJECT_DIR/README.md" ] && [ "$MODE" = "--full" ]; then
  README_EXCERPT=$(head -10 "$PROJECT_DIR/README.md" 2>/dev/null || echo "")
fi

# ─── Output ──────────────────────────────────────────────────────
if [ "$OUTPUT_FMT" = "json" ]; then
  if command -v jq &>/dev/null; then
    # Build file_counts object
    file_counts_json="{"
    first=true
    for entry in "${FILE_COUNTS[@]:-}"; do
      if [[ "$entry" == *":"* ]]; then
        ext="${entry%%:*}"
        count="${entry#*:}"
        [ "$first" = false ] && file_counts_json+=","
        file_counts_json+="\"$ext\":$count"
        first=false
      fi
    done
    file_counts_json+="}"

    # Build dirs object
    dirs_json="{"
    first=true
    for entry in "${TOP_DIRS[@]:-}"; do
      if [[ "$entry" == *":"* ]]; then
        name="${entry%%:*}"
        items="${entry#*:}"
        [ "$first" = false ] && dirs_json+=","
        dirs_json+="\"$name\":$items"
        first=false
      fi
    done
    dirs_json+="}"

    # Build entry_points and config_files arrays
    entry_points_json=$(printf '%s\n' "${ENTRY_POINTS[@]:-}" | jq -R -s 'split("\n") | map(select(length > 0))')
    config_files_json=$(printf '%s\n' "${CONFIG_FILES[@]:-}" | jq -R -s 'split("\n") | map(select(length > 0))')

    jq -n \
      --arg directory "$(pwd)" \
      --argjson file_counts "$file_counts_json" \
      --argjson loc "${TOTAL_LOC:-0}" \
      --argjson dirs "$dirs_json" \
      --argjson entry_points "$entry_points_json" \
      --argjson config_files "$config_files_json" \
      '{
        directory: $directory,
        file_counts: $file_counts,
        estimated_loc: $loc,
        top_level_dirs: $dirs,
        entry_points: $entry_points,
        config_files: $config_files
      }' 2>/dev/null || echo '{"error": "json generation failed"}'
  else
    python3 -c "
import json

file_counts = {}
for entry in '''${FILE_COUNTS[*]:-}'''.split():
    if ':' in entry:
        ext, count = entry.split(':', 1)
        file_counts[ext] = int(count)

dirs = {}
for entry in '''${TOP_DIRS[*]:-}'''.split():
    if ':' in entry:
        name, items = entry.split(':', 1)
        dirs[name] = int(items)

data = {
    'directory': '$(pwd)',
    'file_counts': file_counts,
    'estimated_loc': int('${TOTAL_LOC:-0}' or '0'),
    'top_level_dirs': dirs,
    'entry_points': [e for e in '''${ENTRY_POINTS[*]:-}'''.split() if e],
    'config_files': [c for c in '''${CONFIG_FILES[*]:-}'''.split() if c],
}

print(json.dumps(data, indent=2))
" 2>/dev/null || echo '{"error": "json serialization failed"}'
  fi
else
  text_header "PROJECT SUMMARY"
  text_kv "dir" "$(pwd)"

  text_subsection "file counts"
  for entry in "${FILE_COUNTS[@]:-}"; do
    ext="${entry%%:*}"
    count="${entry#*:}"
    text_item ".${ext}: ${count}"
  done

  echo ""
  text_kv "estimated LOC" "${TOTAL_LOC}"

  text_subsection "structure (top-level)"
  for entry in "${TOP_DIRS[@]:-}"; do
    name="${entry%%:*}"
    items="${entry#*:}"
    text_item "${name}/ (${items} items)"
  done

  text_subsection "entry points"
  if [ ${#ENTRY_POINTS[@]} -gt 0 ]; then
    for f in "${ENTRY_POINTS[@]}"; do text_item "$f"; done
  else
    text_item "(none detected)"
  fi

  text_subsection "config files"
  for f in "${CONFIG_FILES[@]:-}"; do text_item "$f"; done

  if [ -n "$NPM_SCRIPTS" ]; then
    text_subsection "npm scripts"
    echo "$NPM_SCRIPTS" | sed 's/^/  /'
  fi

  if [ -n "$README_EXCERPT" ]; then
    text_subsection "README (first 10 lines)"
    echo "$README_EXCERPT"
  fi

  text_footer "PROJECT SUMMARY"
fi
