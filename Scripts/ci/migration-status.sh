#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL_PKG="$ROOT_DIR/Packages/FountainTooling"
APPS_PKG="$ROOT_DIR/Packages/FountainApps"
SPECS_DIR="$ROOT_DIR/Packages/FountainSpecCuration/openapi/v1"
STORE_DIR="${FOUNTAINSTORE_DIR:-$ROOT_DIR/.fountain/store}"

declare -A MAP=(
  ["planner.yml"]="fountain.coach/agent/planner/service"
  ["function-caller.yml"]="fountain.coach/agent/function-caller/service"
  ["persist.yml"]="fountain.coach/agent/persist/service"
  ["baseline-awareness.yml"]="fountain.coach/agent/baseline-awareness/service"
  ["bootstrap.yml"]="fountain.coach/agent/bootstrap/service"
)

echo "[migration-status] store=$STORE_DIR"
mkdir -p "$STORE_DIR" "$ROOT_DIR/.fountain/logs" "$ROOT_DIR/.fountain/pids" "$ROOT_DIR/.fountain/artifacts"

swift build --package-path "$TOOL_PKG" -c debug --target openapi-to-facts >/dev/null
swift build --package-path "$APPS_PKG" -c debug --target gateway-server >/dev/null

status_json="{\"services\":["
first=1
port=8910
for spec in "${!MAP[@]}"; do
  agent="${MAP[$spec]}"; port=$((port+1))
  spec_path="$SPECS_DIR/$spec"
  if [[ ! -f "$spec_path" ]]; then echo "[migration-status] WARN: missing $spec_path"; continue; fi

  echo "[migration-status] $spec → seed facts for $agent"
  FOUNTAINSTORE_DIR="$STORE_DIR" \
    swift run --package-path "$TOOL_PKG" -c debug openapi-to-facts "$spec_path" --agent-id "$agent" --seed >/dev/null || true

  echo "[migration-status] start gateway on :$port (agent=$agent)"
  FOUNTAIN_SKIP_LAUNCHER_SIG=1 FOUNTAINSTORE_DIR="$STORE_DIR" GATEWAY_AGENT_ID="$agent" GATEWAY_PORT="$port" \
    nohup swift run --package-path "$APPS_PKG" -c debug gateway-server > "$ROOT_DIR/.fountain/logs/gateway-$port.log" 2>&1 &
  pid=$!; sleep 1
  for i in {1..40}; do
    code=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$port/ready" || true)
    [[ "$code" == "200" ]] && break
    sleep 1
  done
  facts_code=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$port/.well-known/agent-facts" || true)
  desc_code=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$port/.well-known/agent-descriptor" || true)
  kill $pid || true
  svc_json="{\"agentId\":\"$agent\",\"spec\":\"$spec\",\"descriptor\":$desc_code,\"facts\":$facts_code}"
  if [[ $first -eq 1 ]]; then status_json+="$svc_json"; first=0; else status_json+=",$svc_json"; fi
done
status_json+="]}"
echo "$status_json" | tee "$ROOT_DIR/.fountain/artifacts/migration-status.json"
echo "[migration-status] ✅ done"

