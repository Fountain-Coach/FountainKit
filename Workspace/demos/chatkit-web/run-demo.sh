#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DEMO_DIR="$ROOT/Workspace/demos/chatkit-web"
LOG_DIR="$DEMO_DIR/.demo-logs"
GATEWAY_PORT="${GATEWAY_PORT:-8010}"
DEMO_PORT="${DEMO_PORT:-8085}"
LAUNCHER_SIGNATURE_VALUE="${LAUNCHER_SIGNATURE:-B86D7CEE-24C4-4C4C-A107-8D0542D1965B}"
GATEWAY_LOG="$LOG_DIR/gateway.log"
SERVER_LOG="$LOG_DIR/server.log"

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[demo] Missing dependency: $1" >&2
    exit 1
  fi
}

cleanup() {
  if [[ -n "${GATEWAY_PID:-}" ]] && ps -p "$GATEWAY_PID" >/dev/null 2>&1; then
    echo "[demo] Stopping gateway server (pid $GATEWAY_PID)…"
    kill "$GATEWAY_PID" >/dev/null 2>&1 || true
    wait "$GATEWAY_PID" 2>/dev/null || true
  fi
}

wait_for_gateway() {
  local attempts=30
  local url="http://127.0.0.1:${GATEWAY_PORT}/health"
  for ((i = 1; i <= attempts; i++)); do
    if curl -sSf "$url" >/dev/null 2>&1; then
      echo "[demo] Gateway is ready on $url"
      return 0
    fi
    sleep 1
  done
  echo "[demo] Gateway failed to start after $attempts attempts."
  echo "[demo] Tail of gateway log:"
  tail -n 20 "$GATEWAY_LOG" 2>/dev/null || true
  return 1
}

open_browser() {
  local url="http://127.0.0.1:${DEMO_PORT}/Workspace/demos/chatkit-web/"
  if command -v open >/dev/null 2>&1; then
    open "$url" >/dev/null 2>&1 || true
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" >/dev/null 2>&1 || true
  fi
  echo "[demo] Demo available at: $url"
}

require "swift"
require "python3"
require "curl"

mkdir -p "$LOG_DIR"
trap cleanup EXIT

echo "[demo] Launching gateway server on port ${GATEWAY_PORT}…"
(
  cd "$ROOT"
  LAUNCHER_SIGNATURE="$LAUNCHER_SIGNATURE_VALUE" \
  GATEWAY_PORT="$GATEWAY_PORT" \
  swift run --package-path Packages/FountainApps gateway-server
) >"$GATEWAY_LOG" 2>&1 &
GATEWAY_PID=$!

wait_for_gateway

# Enforce stable demo port; fail fast if it's busy
python3 - "$DEMO_PORT" <<'PY'
import socket, sys
p = int(sys.argv[1])
s = socket.socket()
try:
    s.bind(("127.0.0.1", p))
    s.close()
    sys.exit(0)
except OSError:
    sys.exit(2)
PY
rc=$?
if [[ $rc -ne 0 ]]; then
  echo "[demo] Port $DEMO_PORT is already in use."
  echo "[demo] Use DEMO_PORT=XXXX ./Workspace/demos/chatkit-web/run-demo.sh to select a different port,"
  echo "[demo] or open the gateway-hosted UI at: http://127.0.0.1:${GATEWAY_PORT}/"
  exit 2
fi

echo "[demo] Starting static server on http://127.0.0.1:${DEMO_PORT}/"
open_browser
cd "$ROOT"
python3 -m http.server "$DEMO_PORT" --directory "$ROOT" 2>&1 | tee "$SERVER_LOG"
