#!/usr/bin/env bash
set -euo pipefail

# mvk-runtime-probe.sh — Boot the MVK runtime server and probe key endpoints
# Usage:
#   bash Scripts/ci/mvk-runtime-probe.sh [--package-path Packages/FountainApps]

PKG_PATH="Packages/FountainApps"
if [[ "${1:-}" == "--package-path" ]]; then
  PKG_PATH="${2:-Packages/FountainApps}"
fi

echo "[mvk-runtime-probe] Building metalviewkit-runtime-server (package: $PKG_PATH)" >&2
swift build --package-path "$PKG_PATH" -c debug --target metalviewkit-runtime-server >/dev/null

BIN="$(swift build --package-path "$PKG_PATH" -c debug --show-bin-path)/metalviewkit-runtime-server"

"$BIN" > .fountain/logs/mvk-runtime-probe-stdout.txt 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null || true; wait $PID 2>/dev/null || true' EXIT
sleep 1

BASE="http://127.0.0.1:7777"

curl -sS "$BASE/health" >/dev/null
curl -sS "$BASE/v1/clock" >/dev/null
curl -sS -X POST "$BASE/v1/clock/test/enable" -H 'Content-Type: application/json' -d '{"startNs":"0"}' >/dev/null
curl -sS -X POST "$BASE/v1/clock/test/advance" -H 'Content-Type: application/json' -d '{"deltaNs":"1000"}' >/dev/null

# Inject and read back via server buffer
W0=$(( (0x4 << 28) | (0 << 24) | (0xB << 20) | (0 << 16) | (1 << 8) ))
W1=$((0x7F))
BODY=$(printf '{"events":[{"tNs":"0","packet":{"w0":%d,"w1":%d}}]}' "$W0" "$W1")
curl -sS -X POST "$BASE/v1/midi/events" -H 'Content-Type: application/json' -d "$BODY" >/dev/null

resp=$(curl -sS "$BASE/v1/midi/vendor?limit=1")
if [[ "${resp}" != *"\"w0\": $W0"* ]]; then
  echo "[mvk-runtime-probe] ERROR: UMP echo mismatch" >&2
  exit 2
fi

echo "[mvk-runtime-probe] OK"

