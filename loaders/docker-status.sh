#!/usr/bin/env bash
# ============================================================================
# docker-status.sh — Docker status loader
# ============================================================================
# Purpose: Reports running Docker containers, compose services, images, and
#          optionally container logs. Detects if Docker is installed/running.
#
# Usage: umwelt docker-status [--full|--minimal] [--json]
#        Or called by profiles/unified-engine as: $LOADERS_DIR/docker-status.sh
#
# Dependencies: bash 3.2+, docker, docker-compose (optional)
#
# Output: Running container count, container names/status, compose services,
#         image list, and recent logs (if --full). Returns "[docker] Not
#         installed" or "[docker] Not running" if unavailable.
# ============================================================================
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

LOG_LINES="${UMWELT_DOCKER_LOG_LINES:-10}"

# ─── Availability Check ─────────────────────────────────────────
DOCKER_INSTALLED=false
DOCKER_RUNNING=false

if command -v docker &>/dev/null; then
  DOCKER_INSTALLED=true
  if docker info &>/dev/null 2>&1; then
    DOCKER_RUNNING=true
  fi
fi

if [ "$DOCKER_INSTALLED" = "false" ] || [ "$DOCKER_RUNNING" = "false" ]; then
  if [ "$OUTPUT_FMT" = "json" ]; then
    if command -v jq &>/dev/null; then
      jq -n \
        --argjson installed "$( [ "$DOCKER_INSTALLED" = "true" ] && echo 'true' || echo 'false' )" \
        '{
          docker_installed: $installed,
          docker_running: false,
          running_containers: [],
          running_count: 0
        }' 2>/dev/null || echo '{"error": "json generation failed"}'
    else
      python3 -c "
import json
print(json.dumps({
    'docker_installed': $( [ \"$DOCKER_INSTALLED\" = \"true\" ] && echo 'True' || echo 'False' ),
    'docker_running': False,
    'running_containers': [],
    'running_count': 0
}, indent=2))
"
    fi
  else
    text_header "DOCKER STATUS"
    if [ "$DOCKER_INSTALLED" = "false" ]; then
      text_kv "docker" "not installed"
    else
      text_kv "docker" "not running"
    fi
    text_footer "DOCKER STATUS"
  fi
  exit 0
fi

# ─── Gather Data ─────────────────────────────────────────────────
RUNNING_COUNT=$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')
STOPPED_COUNT=$(docker ps -a --filter "status=exited" -q 2>/dev/null | wc -l | tr -d ' ')

# Running containers data (JSON-ready format)
if command -v jq &>/dev/null; then
  CONTAINERS_JSON=$(docker ps --format '{{json .}}' 2>/dev/null | jq -s 'map({name: .Names, image: .Image, status: .Status, ports: .Ports, created: .CreatedAt})' 2>/dev/null || echo "[]")
else
  CONTAINERS_JSON=$(docker ps --format '{{json .}}' 2>/dev/null | python3 -c "
import sys, json
containers = []
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        c = json.loads(line)
        containers.append({
            'name': c.get('Names', ''),
            'image': c.get('Image', ''),
            'status': c.get('Status', ''),
            'ports': c.get('Ports', ''),
            'created': c.get('CreatedAt', '')
        })
    except: pass
print(json.dumps(containers))
" 2>/dev/null || echo "[]")
fi

# Compose detection
HAS_COMPOSE=false
for cf in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
  if [ -f "$cf" ]; then HAS_COMPOSE=true; break; fi
done

# Disk usage (full mode)
DISK_USAGE=""
if [ "$MODE" = "--full" ]; then
  DISK_USAGE=$(docker system df --format 'table {{.Type}}\t{{.Size}}\t{{.Reclaimable}}' 2>/dev/null || echo "")
fi

# ─── Output ──────────────────────────────────────────────────────
if [ "$OUTPUT_FMT" = "json" ]; then
  if command -v jq &>/dev/null; then
    jq -n \
      --argjson running_count "$RUNNING_COUNT" \
      --argjson stopped_count "$STOPPED_COUNT" \
      --argjson containers "$CONTAINERS_JSON" \
      --argjson has_compose "$( [ "$HAS_COMPOSE" = "true" ] && echo 'true' || echo 'false' )" \
      '{
        docker_installed: true,
        docker_running: true,
        running_count: $running_count,
        stopped_count: $stopped_count,
        running_containers: $containers,
        has_compose: $has_compose
      }' 2>/dev/null || echo '{"error": "json generation failed"}'
  else
    python3 -c "
import json

data = {
    'docker_installed': True,
    'docker_running': True,
    'running_count': int('$RUNNING_COUNT'),
    'stopped_count': int('$STOPPED_COUNT'),
    'running_containers': json.loads('''$CONTAINERS_JSON''' or '[]'),
    'has_compose': $( [ "$HAS_COMPOSE" = "true" ] && echo 'True' || echo 'False' ),
}

print(json.dumps(data, indent=2))
" 2>/dev/null || echo '{"error": "json serialization failed"}'
  fi
else
  text_header "DOCKER STATUS"
  text_kv "running containers" "${RUNNING_COUNT}"

  if [ "$RUNNING_COUNT" -gt 0 ]; then
    echo ""
    docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null
  fi

  if [ "$MODE" = "--minimal" ]; then
    text_footer "DOCKER STATUS"
    exit 0
  fi

  if [ "$STOPPED_COUNT" -gt 0 ]; then
    echo ""
    text_kv "stopped containers" "${STOPPED_COUNT}"
    docker ps -a --filter "status=exited" --format '  {{.Names}} (exited {{.Status}})' 2>/dev/null | head -5
  fi

  if [ "$HAS_COMPOSE" = "true" ]; then
    text_subsection "compose services"
    docker compose ps 2>/dev/null || docker-compose ps 2>/dev/null || echo "(compose not available)"
  fi

  if [ "$MODE" = "--full" ]; then
    if [ -n "$DISK_USAGE" ]; then
      text_subsection "disk usage"
      echo "$DISK_USAGE"
    fi

    text_subsection "recent logs (last container)"
    LAST=$(docker ps -lq 2>/dev/null)
    if [ -n "${LAST:-}" ]; then
      docker logs --tail "$LOG_LINES" "$LAST" 2>&1 | head -"$LOG_LINES"
    fi
  fi

  text_footer "DOCKER STATUS"
fi
