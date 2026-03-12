#!/usr/bin/env bash
# ============================================================================
# api-health.sh — API health loader
# ============================================================================
# Purpose: Checks health of local development servers and configured API
#          endpoints. Tests common ports (3000, 8000, 5173, etc.) and custom
#          URLs for availability and response times.
#
# Usage: umwelt api-health [--full] [--json]
#        Or called by profiles/unified-engine as: $LOADERS_DIR/api-health.sh
#        Config: UMWELT_LOCAL_PORTS="3000:dev 8000:api"
#                UMWELT_API_ENDPOINTS="http://api.example.com/health"
#
# Dependencies: bash 3.2+, nc or curl for port/endpoint checks
#
# Output: List of active ports with labels, HTTP endpoint health status
#         (UP/DOWN), and response times. Returns "[api-health] No services
#         detected" if no ports or endpoints are responding.
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

# Use configurable port list (from config.sh or default)
PORTS="${UMWELT_LOCAL_PORTS:-3000:dev-server 3001:dev-alt 4000:graphql 5000:flask 5173:vite 5432:postgres 6379:redis 8000:uvicorn 8080:proxy 8443:https-alt 9090:prometheus 27017:mongodb}"

# ─── Check a single port ────────────────────────────────────────
check_port() {
  local port=$1
  local name=$2
  local status
  status=$(curl -s --connect-timeout 2 -o /dev/null -w "%{http_code}" "http://localhost:${port}" 2>/dev/null || echo "000")
  if echo "$status" | grep -qE '(200|301|302|404)'; then
    echo "UP:${port}:${name}:${status}"
  else
    echo "DOWN:${port}:${name}:${status}"
  fi
}

# ─── Gather Data ─────────────────────────────────────────────────
declare -a ACTIVE_SERVICES=()
declare -a CUSTOM_RESULTS=()

for entry in $PORTS; do
  port="${entry%%:*}"
  name="${entry#*:}"
  if lsof -i ":${port}" &>/dev/null 2>&1 || nc -z localhost "$port" &>/dev/null 2>&1; then
    result=$(check_port "$port" "$name")
    ACTIVE_SERVICES+=("$result")
  fi
done

# Custom endpoints from env var
if [ -n "${UMWELT_API_ENDPOINTS:-}" ]; then
  IFS=',' read -ra ENDPOINTS <<< "$UMWELT_API_ENDPOINTS"
  for url in "${ENDPOINTS[@]}"; do
    url=$(echo "$url" | xargs)
    STATUS=$(curl -s --connect-timeout 3 -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "ERR")
    if [ "$STATUS" = "200" ] || [ "$STATUS" = "301" ] || [ "$STATUS" = "302" ]; then
      CUSTOM_RESULTS+=("UP:${url}:${STATUS}")
    else
      CUSTOM_RESULTS+=("DOWN:${url}:${STATUS}")
    fi
  done
fi

# ─── .env API URLs (full mode only) ─────────────────────────────
declare -a ENV_URLS=()
if [ -f ".env" ] && [ "$MODE" = "--full" ]; then
  while IFS= read -r line; do
    KEY=$(echo "$line" | cut -d'=' -f1)
    VALUE=$(echo "$line" | cut -d'=' -f2- | tr -d '"' | tr -d "'")
    if echo "$VALUE" | grep -qiE '(sk-|pk_|key|secret|token)'; then
      ENV_URLS+=("${KEY}=<redacted>")
    else
      ENV_URLS+=("${KEY}=${VALUE}")
    fi
  done < <(grep -iE '(API_URL|BASE_URL|ENDPOINT|SERVER_URL)=' .env 2>/dev/null || true)
fi

# ─── Output ──────────────────────────────────────────────────────
if [ "$OUTPUT_FMT" = "json" ]; then
  if command -v jq &>/dev/null; then
    # Build services array
    services_json="["
    first=true
    for s in "${ACTIVE_SERVICES[@]:-}"; do
      if [ -n "$s" ]; then
        IFS=: read -r status port name http_code <<< "$s"
        [ "$first" = false ] && services_json+=","
        services_json+="{\"status\":\"${status,,}\",\"port\":$port,\"name\":\"$name\",\"http_code\":\"$http_code\"}"
        first=false
      fi
    done
    services_json+="]"

    # Build custom endpoints array
    custom_json="["
    first=true
    for c in "${CUSTOM_RESULTS[@]:-}"; do
      if [ -n "$c" ]; then
        status="${c%%:*}"
        rest="${c#*:}"
        url="${rest%:*}"
        http_code="${rest##*:}"
        [ "$first" = false ] && custom_json+=","
        custom_json+="{\"status\":\"${status,,}\",\"url\":\"$url\",\"http_code\":\"$http_code\"}"
        first=false
      fi
    done
    custom_json+="]"

    # Calculate healthy status
    all_up=true
    for s in "${ACTIVE_SERVICES[@]:-}" "${CUSTOM_RESULTS[@]:-}"; do
      if [ -n "$s" ] && [[ ! "$s" =~ ^UP: ]]; then
        all_up=false
        break
      fi
    done

    jq -n \
      --argjson services "$services_json" \
      --argjson custom "$custom_json" \
      --argjson healthy "$( [ "$all_up" = true ] && echo 'true' || echo 'false' )" \
      '{
        active_services: $services,
        active_count: ($services | length),
        custom_endpoints: $custom,
        healthy: $healthy
      }' 2>/dev/null || echo '{"error": "json generation failed"}'
  else
    python3 -c "
import json

services = []
for s in '''${ACTIVE_SERVICES[*]:-}'''.split():
    if not s: continue
    parts = s.split(':')
    if len(parts) >= 4:
        services.append({
            'status': parts[0].lower(),
            'port': int(parts[1]),
            'name': parts[2],
            'http_code': parts[3]
        })

custom = []
for c in '''${CUSTOM_RESULTS[*]:-}'''.split():
    if not c: continue
    parts = c.split(':', 2)
    if len(parts) >= 3:
        custom.append({
            'status': parts[0].lower(),
            'url': parts[1],
            'http_code': parts[2]
        })

data = {
    'active_services': services,
    'active_count': len(services),
    'custom_endpoints': custom,
    'healthy': all(s['status'] == 'up' for s in services + custom) if (services or custom) else True
}

print(json.dumps(data, indent=2))
" 2>/dev/null || echo '{"error": "json serialization failed"}'
  fi
else
  text_header "API HEALTH"
  text_subsection "local services"

  if [ ${#ACTIVE_SERVICES[@]} -eq 0 ]; then
    text_item "no services detected on common ports"
  else
    for entry in "${ACTIVE_SERVICES[@]}"; do
      status="${entry%%:*}"
      rest="${entry#*:}"
      port="${rest%%:*}"
      rest2="${rest#*:}"
      name="${rest2%%:*}"
      http="${rest2#*:}"
      if [ "$status" = "UP" ]; then
        text_check "${name} (localhost:${port}) — ${http}" "ok"
      else
        text_check "${name} (localhost:${port}) — ${http}" "down"
      fi
    done
  fi

  if [ ${#CUSTOM_RESULTS[@]} -gt 0 ]; then
    text_subsection "custom endpoints"
    for entry in "${CUSTOM_RESULTS[@]}"; do
      status="${entry%%:*}"
      rest="${entry#*:}"
      url="${rest%:*}"
      http="${rest##*:}"
      if [ "$status" = "UP" ]; then
        text_check "${url} — ${http}" "ok"
      else
        text_check "${url} — ${http}" "down"
      fi
    done
  fi

  if [ ${#ENV_URLS[@]} -gt 0 ]; then
    text_subsection ".env API URLs"
    for line in "${ENV_URLS[@]}"; do
      text_item "${line}"
    done
  fi

  text_footer "API HEALTH"
fi
