#!/usr/bin/env bash
set -euo pipefail

# Live validation of OpenAPI → facts parity by exercising mapped endpoints.
# Env:
#  - SPEC_FILE: spec filename under Packages/FountainSpecCuration/openapi/v1 (e.g., baseline-awareness.yml)
#  - AGENT_ID: agent id used for facts (e.g., fountain.coach/agent/baseline-awareness/service)
#  - SERVER_TARGET: SwiftPM executable target to run (e.g., baseline-awareness-server)
#  - PORT_ENV: Environment variable name for the server port (e.g., BASELINE_AWARENESS_PORT)
#  - PORT: Port number to listen on (e.g., 8001)

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL_PKG="$ROOT_DIR/Packages/FountainTooling"
APPS_PKG="$ROOT_DIR/Packages/FountainApps"
SPEC_DIR="$ROOT_DIR/Packages/FountainSpecCuration/openapi/v1"

SPEC_FILE="${SPEC_FILE:?SPEC_FILE is required}"
AGENT_ID="${AGENT_ID:?AGENT_ID is required}"
SERVER_TARGET="${SERVER_TARGET:?SERVER_TARGET is required}"
PORT_ENV="${PORT_ENV:?PORT_ENV is required}"
PORT="${PORT:?PORT is required}"

STORE_DIR="${FOUNTAINSTORE_DIR:-$ROOT_DIR/.fountain/store}"
mkdir -p "$STORE_DIR" "$ROOT_DIR/.fountain/logs" "$ROOT_DIR/.fountain/pids"

SPEC_PATH="$SPEC_DIR/$SPEC_FILE"
if [[ ! -f "$SPEC_PATH" ]]; then echo "[facts-validate] ERROR: missing spec $SPEC_PATH" >&2; exit 1; fi

echo "[facts-validate] building tool and $SERVER_TARGET..."
swift build --package-path "$TOOL_PKG" -c debug --target openapi-to-facts >/dev/null
swift build --package-path "$APPS_PKG" -c debug --target "$SERVER_TARGET" >/dev/null

echo "[facts-validate] seeding facts from $SPEC_FILE for $AGENT_ID"
FOUNTAINSTORE_DIR="$STORE_DIR" \
  swift run --package-path "$TOOL_PKG" -c debug openapi-to-facts "$SPEC_PATH" --agent-id "$AGENT_ID" --seed >/dev/null

echo "[facts-validate] starting $SERVER_TARGET on :$PORT"
env FOUNTAIN_SKIP_LAUNCHER_SIG=1 FOUNTAINSTORE_DIR="$STORE_DIR" "$PORT_ENV=$PORT" \
  nohup swift run --package-path "$APPS_PKG" -c debug "$SERVER_TARGET" > "$ROOT_DIR/.fountain/logs/$SERVER_TARGET-$PORT.log" 2>&1 &
PID=$!
trap 'kill $PID || true' EXIT

# Wait for readiness (metrics is cheap and available on all services)
for i in {1..60}; do
  code=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$PORT/metrics" || true)
  [[ "$code" == "200" ]] && break
  sleep 1
done

echo "[facts-validate] generating facts for live validation"
TMP_GEN="$(mktemp)"
swift run --package-path "$TOOL_PKG" -c debug openapi-to-facts "$SPEC_PATH" --agent-id "$AGENT_ID" > "$TMP_GEN"

echo "[facts-validate] validating mapped operations with samples (POST/PUT/PATCH only)"
BASE_URL="http://127.0.0.1:$PORT"
SAMPLE_COUNT=$(jq '([.functionBlocks[]?.properties[]? | select((.mapsTo.openapi.method == "POST" or .mapsTo.openapi.method == "PUT" or .mapsTo.openapi.method == "PATCH") and (.samples.request != null))] | length)' "$TMP_GEN")
if [[ "$SAMPLE_COUNT" -eq 0 ]]; then
  echo "[facts-validate] ERROR: no sample-bearing writable properties found in facts" >&2
  exit 1
fi
idx=0
while read -r line; do
  method=$(echo "$line" | cut -d$'\t' -f1)
  path=$(echo "$line" | cut -d$'\t' -f2)
  body=$(echo "$line" | cut -d$'\t' -f3-)
  code=$(curl -s -o /dev/null -w "%{http_code}" -X "$method" -H 'Content-Type: application/json' --data "$body" "$BASE_URL$path" || true)
  echo "[facts-validate] $method $path -> $code"
  if [[ "$code" != "200" && "$code" != "201" && "$code" != "202" ]]; then
    echo "[facts-validate] ERROR: $method $path returned $code" >&2
    exit 1
  fi
  idx=$((idx+1))
done < <(jq -r '.functionBlocks[]?.properties[]? | select((.mapsTo.openapi.method == "POST" or .mapsTo.openapi.method == "PUT" or .mapsTo.openapi.method == "PATCH") and (.samples.request != null)) | [.mapsTo.openapi.method, .mapsTo.openapi.path, (.samples.request | tojson)] | @tsv' "$TMP_GEN")

echo "[facts-validate] ✅ live parity ok for $SERVER_TARGET ($idx operations)"
