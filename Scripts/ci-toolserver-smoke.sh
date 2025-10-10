#!/usr/bin/env bash
set -euo pipefail

# Optional CI smoke for tool-server. Enable by setting CI_TOOLSERVER_SMOKE=1.
[[ "${CI_TOOLSERVER_SMOKE:-0}" == "1" ]] || { echo "[ci-toolserver] skipped (CI_TOOLSERVER_SMOKE!=1)"; exit 0; }

if ! command -v docker >/dev/null 2>&1; then
  echo "[ci-toolserver] docker not available; skipping" ; exit 0
fi

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)
export LAUNCHER_SIGNATURE=${LAUNCHER_SIGNATURE:-B86D7CEE-24C4-4C4C-A107-8D0542D1965B}
PORT=${PORT:-8012}

echo "[ci-toolserver] Build tool-server (debug)…"
swift build --package-path "$ROOT/Packages/FountainApps" --product tool-server -c debug

echo "[ci-toolserver] Start tool-server…"
TOOLSERVER_PULL_ON_START=0 "$ROOT"/.build/debug/tool-server >"$ROOT"/.build/tool-server.log 2>&1 &
PID=$!
trap 'kill $PID || true' EXIT

echo "[ci-toolserver] Wait for status…"
for i in {1..20}; do
  if curl -sf --max-time 3 "http://127.0.0.1:$PORT/_status" >/dev/null; then break; fi
  sleep 0.5
done

echo "[ci-toolserver] Query status…"
curl -sf "http://127.0.0.1:$PORT/_status" | sed -e 's/\s\+/ /g' | cut -c1-200

echo "[ci-toolserver] OK"
