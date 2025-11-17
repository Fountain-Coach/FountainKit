#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL_PKG="$ROOT_DIR/Packages/FountainTooling"
APPS_PKG="$ROOT_DIR/Packages/FountainApps"
SPEC_DIR="$ROOT_DIR/Packages/FountainSpecCuration/openapi/v1"

: "${FOUNTAINSTORE_DIR:=$ROOT_DIR/.fountain/store}"
: "${AGENT_ID:=fountain.coach/agent/planner/service}"
: "${SPEC_FILE:=planner.yml}"
: "${PORT:=8900}"

echo "[facts-smoke] store=$FOUNTAINSTORE_DIR agent=$AGENT_ID spec=$SPEC_FILE port=$PORT"

mkdir -p "$FOUNTAINSTORE_DIR" "$ROOT_DIR/.fountain/logs" "$ROOT_DIR/.fountain/pids"

echo "[facts-smoke] building generator…"
swift build --package-path "$TOOL_PKG" -c debug --target openapi-to-facts >/dev/null

SPEC_PATH="$SPEC_DIR/$SPEC_FILE"
if [[ ! -f "$SPEC_PATH" ]]; then
  echo "[facts-smoke] ERROR: missing spec $SPEC_PATH" >&2
  exit 1
fi

echo "[facts-smoke] seeding facts from $SPEC_PATH → $AGENT_ID"
FOUNTAINSTORE_DIR="$FOUNTAINSTORE_DIR" \
  swift run --package-path "$TOOL_PKG" -c debug openapi-to-facts "$SPEC_PATH" --agent-id "$AGENT_ID" --seed --allow-tools-only >/dev/null

echo "[facts-smoke] building gateway-server…"
swift build --package-path "$APPS_PKG" -c debug --target gateway-server >/dev/null

echo "[facts-smoke] starting gateway-server on port $PORT…"
FOUNTAIN_SKIP_LAUNCHER_SIG=1 FOUNTAINSTORE_DIR="$FOUNTAINSTORE_DIR" GATEWAY_AGENT_ID="$AGENT_ID" GATEWAY_PORT="$PORT" \
  nohup swift run --package-path "$APPS_PKG" -c debug gateway-server > "$ROOT_DIR/.fountain/logs/gateway-$PORT.log" 2>&1 &
PID=$!
echo $PID > "$ROOT_DIR/.fountain/pids/gateway-$PORT.pid"

trap 'kill $PID || true' EXIT

echo "[facts-smoke] waiting for /ready…"
for i in {1..60}; do
  code=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$PORT/ready" || true)
  if [[ "$code" == "200" ]]; then echo "[facts-smoke] ready"; break; fi
  sleep 1
done
if [[ "$code" != "200" ]]; then
  echo "[facts-smoke] ERROR: /ready returned $code" >&2
  exit 1
fi

echo "[facts-smoke] fetching /.well-known/agent-facts…"
code=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$PORT/.well-known/agent-facts" || true)
if [[ "$code" != "200" ]]; then
  echo "[facts-smoke] ERROR: /.well-known/agent-facts returned $code" >&2
  echo "--- gateway log ---"; tail -n +1 "$ROOT_DIR/.fountain/logs/gateway-$PORT.log" || true; echo "--- end log ---"
  exit 1
fi
curl -s "http://127.0.0.1:$PORT/.well-known/agent-facts" | head -n 80
echo "[facts-smoke] ✅ facts served"
