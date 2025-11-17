#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL_PKG="$ROOT_DIR/Packages/FountainTooling"
APPS_PKG="$ROOT_DIR/Packages/FountainApps"
SPEC_DIR="$ROOT_DIR/Packages/FountainSpecCuration/openapi/v1"

: "${FOUNTAINSTORE_DIR:=$ROOT_DIR/.fountain/store}"
: "${SPEC_FILE:=planner.yml}"
: "${AGENT_ID:=fountain.coach/agent/planner/service}"
: "${PORT:=8920}"

echo "[facts-parity] spec=$SPEC_FILE agent=$AGENT_ID store=$FOUNTAINSTORE_DIR port=$PORT"

mkdir -p "$FOUNTAINSTORE_DIR" "$ROOT_DIR/.fountain/logs" "$ROOT_DIR/.fountain/pids"
SPEC_PATH="$SPEC_DIR/$SPEC_FILE"
if [[ ! -f "$SPEC_PATH" ]]; then
  echo "[facts-parity] ERROR: missing spec $SPEC_PATH" >&2
  exit 1
fi

echo "[facts-parity] building tool and gateway…"
swift build --package-path "$TOOL_PKG" -c debug --target openapi-to-facts >/dev/null
swift build --package-path "$APPS_PKG" -c debug --target gateway-server >/dev/null

TMP_GEN="$(mktemp)"; TMP_SERVED="$(mktemp)"

echo "[facts-parity] generating facts from spec…"
swift run --package-path "$TOOL_PKG" -c debug openapi-to-facts "$SPEC_PATH" --agent-id "$AGENT_ID" --allow-tools-only > "$TMP_GEN"

echo "[facts-parity] seeding facts and starting gateway…"
FOUNTAINSTORE_DIR="$FOUNTAINSTORE_DIR" \
  swift run --package-path "$TOOL_PKG" -c debug openapi-to-facts "$SPEC_PATH" --agent-id "$AGENT_ID" --seed --allow-tools-only >/dev/null
FOUNTAIN_SKIP_LAUNCHER_SIG=1 FOUNTAINSTORE_DIR="$FOUNTAINSTORE_DIR" GATEWAY_AGENT_ID="$AGENT_ID" GATEWAY_PORT="$PORT" \
  nohup swift run --package-path "$APPS_PKG" -c debug gateway-server > "$ROOT_DIR/.fountain/logs/gateway-$PORT.log" 2>&1 &
PID=$!
trap 'kill $PID || true' EXIT

for i in {1..60}; do
  code=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$PORT/ready" || true)
  [[ "$code" == "200" ]] && break
  sleep 1
done

curl -fsS "http://127.0.0.1:$PORT/.well-known/agent-facts" > "$TMP_SERVED"

echo "[facts-parity] comparing generated vs served facts (property mapping)…"
canon() {
  jq '[.functionBlocks[]?.properties[]? | {id, m:(.mapsTo.openapi.method? // "GET"), p:(.mapsTo.openapi.path? // ""), b:(.mapsTo.openapi.body? // null)}] | sort_by(.id, .m, .p, .b)'
}

GEN_C=$(cat "$TMP_GEN" | canon)
SRV_C=$(cat "$TMP_SERVED" | canon)
if ! diff -u <(echo "$GEN_C") <(echo "$SRV_C") >/dev/null; then
  echo "[facts-parity] ERROR: served facts differ from generated facts" >&2
  echo "--- generated ---"; echo "$GEN_C"; echo "--- served ---"; echo "$SRV_C"
  exit 1
fi

echo "[facts-parity] ✅ parity ok"
