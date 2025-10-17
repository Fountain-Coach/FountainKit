#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEV_DIR="$ROOT/Workspace/chatkit-dev"
LOG_DIR="$DEV_DIR/.dev-logs"
GATEWAY_PORT_DEFAULT="${GATEWAY_PORT:-8010}"
DEV_PORT_DEFAULT="${DEV_PORT:-5173}"
CHATKIT_RESPONDER_DEFAULT="${CHATKIT_RESPONDER:-llm}"
LAUNCHER_SIGNATURE_VALUE="${LAUNCHER_SIGNATURE:-B86D7CEE-24C4-4C4C-A107-8D0542D1965B}"
GATEWAY_LOG="$LOG_DIR/gateway.log"

cleanup() {
  if [[ -n "${GATEWAY_PID:-}" ]] && ps -p "$GATEWAY_PID" >/dev/null 2>&1; then
  echo "[dev] Stopping gateway (pid $GATEWAY_PID)..."
    kill "$GATEWAY_PID" >/dev/null 2>&1 || true
    wait "$GATEWAY_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

require() { command -v "$1" >/dev/null 2>&1 || { echo "[dev] Missing $1"; exit 1; }; }
require swift
require node
require lsof

mkdir -p "$LOG_DIR"

# Find a free TCP port (trial-and-error) starting at the provided base,
# using lsof to avoid IPv4/IPv6 ambiguity.
find_free_port() {
  local start="$1"
  local end=$((start + 30))
  for p in $(seq "$start" "$end"); do
    if ! lsof -nP -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1; then
      echo "$p"; return 0
    fi
  done
  echo "$start"
}

# Select ports (trial-and-error) without killing foreign processes
GATEWAY_PORT="$(find_free_port "$GATEWAY_PORT_DEFAULT")"
DEV_PORT="$(find_free_port "$DEV_PORT_DEFAULT")"

echo "[dev] Launching gateway on :$GATEWAY_PORT..."
(
  cd "$ROOT"
  LAUNCHER_SIGNATURE="$LAUNCHER_SIGNATURE_VALUE" \
  CHATKIT_RESPONDER="$CHATKIT_RESPONDER_DEFAULT" \
  GATEWAY_PORT="$GATEWAY_PORT" \
  swift run --package-path Packages/FountainApps gateway-server
) >"$GATEWAY_LOG" 2>&1 &
GATEWAY_PID=$!

# Quick readiness wait
for i in {1..30}; do
  if curl -sSf "http://127.0.0.1:${GATEWAY_PORT}/health" >/dev/null 2>&1; then
    echo "[dev] Gateway ready."
    break
  fi
  sleep 1
done

cd "$DEV_DIR"
echo "[dev] Starting Vite on :$DEV_PORT (gateway http://127.0.0.1:${GATEWAY_PORT})..."
if command -v pnpm >/dev/null 2>&1; then
  pnpm install
  GATEWAY_URL="http://127.0.0.1:${GATEWAY_PORT}" pnpm vite --port "$DEV_PORT"
else
  npm install
  GATEWAY_URL="http://127.0.0.1:${GATEWAY_PORT}" npx vite --port "$DEV_PORT"
fi
