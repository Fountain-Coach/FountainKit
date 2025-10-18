#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
readability-smoke.sh — End-to-end check for .fountain scene rendering

Usage:
  $(basename "$0") [--port <n>] [--keep]

Options:
  --port <n>  Port for test persist-server (default: 8599)
  --keep      Keep temp directory and logs on exit

Requires: swift, curl, jq (for simple assertions)
USAGE
}

PORT=8599
KEEP=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) PORT=${2:-8599}; shift 2;;
    --keep) KEEP=1; shift 1;;
    --help|-h) usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2;;
  esac
done

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")"/../.. && pwd)
TMP=$(mktemp -d 2>/dev/null || mktemp -d -t fk_readability)
LOG="$TMP/persist.log"
FNT="$TMP/sample.fountain"

cleanup() {
  if [[ -f "$TMP/pid" ]]; then
    kill $(cat "$TMP/pid") >/dev/null 2>&1 || true
  fi
  if (( KEEP )); then
    echo "[smoke] Temp kept at: $TMP"
  else
    rm -rf "$TMP"
  fi
}
trap cleanup EXIT INT TERM

cat >"$FNT" <<'FOUNTAIN'
As You Like It
**** ACT I ****
**** SCENE II. Lawn before the Duke's palace. ****
CELIA
Yonder, sure, they are coming: let us now stay and see it.
ORLANDO
I beseech you, punish me not with your hard thoughts.
FOUNTAIN

echo "[smoke] Building persist-server…"
swift build --package-path "$ROOT/Packages/FountainApps" --target persist-server >/dev/null

echo "[smoke] Starting persist-server on :$PORT"
env LAUNCHER_SIGNATURE="B86D7CEE-24C4-4C4C-A107-8D0542D1965B" \
    FOUNTAINSTORE_PORT="$PORT" \
    FOUNTAIN_SOURCE_PATH="$FNT" \
    "$ROOT/Packages/FountainApps/.build/debug/persist-server" \
    >"$LOG" 2>&1 & echo $! >"$TMP/pid"

# Wait for readiness
for i in {1..60}; do
  if curl -sf "http://127.0.0.1:$PORT/metrics" >/dev/null 2>&1; then
    echo "[smoke] persist up"
    break
  fi
  sleep 0.2
  if (( i == 60 )); then echo "[smoke] persist failed to come up" >&2; exit 1; fi
done

echo "[smoke] Probing scene script (JSON)…"
HDR=$(curl -sf -X POST "http://127.0.0.1:$PORT/arcs/the-four-stars/speeches/script" \
  -H 'Content-Type: application/json' \
  -d '{"act":"I","scene":"II","format":"json"}' | jq -r '.result.header')
echo "[smoke] Header: $HDR"
[[ "$HDR" == Act\ I\ Scene\ II* ]] || { echo "[smoke] bad header" >&2; exit 1; }

echo "[smoke] Probing scene script (layout=screenplay)…"
SPK=$(curl -sf -X POST "http://127.0.0.1:$PORT/arcs/the-four-stars/speeches/script" \
  -H 'Content-Type: application/json' \
  -d '{"act":"I","scene":"II","format":"json","layout":"screenplay"}' | jq -r '.result.blocks[0].speaker')
echo "[smoke] First speaker: $SPK"
[[ "$SPK" == "CELIA" ]] || { echo "[smoke] unexpected first speaker" >&2; exit 1; }

echo "[smoke] OK"
