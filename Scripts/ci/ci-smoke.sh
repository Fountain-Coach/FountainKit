#!/usr/bin/env bash
set -euo pipefail

# FountainKit CI smoke test: bring up core services, probe readiness, tear down.

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")"/../.. && pwd)
export LAUNCHER_SIGNATURE=${LAUNCHER_SIGNATURE:-B86D7CEE-24C4-4C4C-A107-8D0542D1965B}

echo "[ci-smoke] Building FountainApps (debug)…"
swift build --package-path "$ROOT/Packages/FountainApps" -c debug

echo "[ci-smoke] Starting core services with readiness checks…"
DEV_UP_USE_BIN=1 DEV_UP_NO_START_LOCAL_AGENT=1 DEV_UP_CHECKS=1 \
  bash "$ROOT/Scripts/dev-up"

echo "[ci-smoke] Status snapshot:"
bash "$ROOT/Scripts/dev-status" || true

echo "[ci-smoke] Probing gateway metrics…"
curl -sf --max-time 5 http://127.0.0.1:8010/metrics >/dev/null

echo "[ci-smoke] Probing planner metrics…"
curl -sf --max-time 5 http://127.0.0.1:8003/metrics >/dev/null

echo "[ci-smoke] Probing function-caller metrics…"
curl -sf --max-time 5 http://127.0.0.1:8004/metrics >/dev/null

echo "[ci-smoke] Probing persist metrics…"
curl -sf --max-time 5 http://127.0.0.1:8005/metrics >/dev/null

echo "[ci-smoke] Exercising gateway ChatKit flows via generated client…"
GATEWAY_BASE_URL=${GATEWAY_BASE_URL:-http://127.0.0.1:8010} \
  swift run --package-path "$ROOT/Packages/FountainApps" gateway-ci-smoke

echo "[ci-smoke] Shutting down…"
bash "$ROOT/Scripts/dev-down" --force

echo "[ci-smoke] OK"

