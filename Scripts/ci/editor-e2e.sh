#!/usr/bin/env bash
set -euo pipefail

PORT=${PORT:-8085}
CID=${CID:-fountain-editor-e2e}
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PKG_PATH="$ROOT_DIR/Packages/FountainApps"

echo "[editor-e2e] Building fountain-editor-service-server…"
swift build --package-path "$PKG_PATH" -c debug --target fountain-editor-service-server >/dev/null

BIN=$(ls -1 "$PKG_PATH"/.build/*/debug/fountain-editor-service-server 2>/dev/null | head -n1 || true)
if [[ -z "$BIN" ]]; then echo "[editor-e2e] ERROR: binary not found" >&2; exit 2; fi

echo "[editor-e2e] Starting server on :$PORT …"
FOUNTAIN_SKIP_LAUNCHER_SIG=1 PORT=$PORT "$BIN" >/dev/null 2>&1 &
SRV_PID=$!
trap 'kill $SRV_PID 2>/dev/null || true' EXIT

health() { curl -sf "http://localhost:$PORT/editor/health"; }
retry() { local n=0; until "$@"; do n=$((n+1)); [[ $n -ge 30 ]] && return 1; sleep 0.2; done; }

echo "[editor-e2e] Waiting for health…"
retry health >/dev/null || { echo "[editor-e2e] server not healthy" >&2; exit 3; }

base() { echo "http://localhost:$PORT/editor/$CID"; }

echo "[editor-e2e] ETag flow create…"
curl -sS -o /dev/null -w "%{http_code}" -X PUT -H 'If-Match: *' -H 'Content-Type: text/plain' --data-binary 'Hello' "$(base)/script" | grep -q '^204$'

echo "[editor-e2e] GET script…"
ETAG1=$(curl -sS -i "$(base)/script" | awk -F': ' '/^ETag:/ {gsub("\r","",$2); print $2; exit}')
[[ ${#ETAG1} -eq 8 ]] || { echo "[editor-e2e] bad ETag1" >&2; exit 4; }

echo "[editor-e2e] Mismatch PUT…"
curl -sS -o /dev/null -w "%{http_code}" -X PUT -H 'If-Match: deadbeef' -H 'Content-Type: text/plain' --data-binary 'Hello again' "$(base)/script" | grep -q '^412$'

echo "[editor-e2e] Correct PUT…"
curl -sS -o /dev/null -w "%{http_code}" -X PUT -H "If-Match: $ETAG1" -H 'Content-Type: text/plain' --data-binary 'Hello world!' "$(base)/script" | grep -q '^204$'

ETAG2=$(curl -sS -i "$(base)/script" | awk -F': ' '/^ETag:/ {gsub("\r","",$2); print $2; exit}')
[[ "$ETAG2" != "$ETAG1" ]] || { echo "[editor-e2e] ETag did not advance" >&2; exit 5; }

echo "[editor-e2e] Instruments create…"
CREATE_JSON='{"name":"Piano","profile":"midi2sampler"}'
RESP=$(curl -sS -H 'Content-Type: application/json' -d "$CREATE_JSON" "$(base)/instruments")
IID=$(printf '%s' "$RESP" | sed -n 's/.*"instrumentId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
[[ -n "$IID" ]] || { echo "[editor-e2e] instrumentId missing" >&2; echo "$RESP"; exit 6; }

echo "[editor-e2e] Instruments patch…"
curl -sS -o /dev/null -w "%{http_code}" -X PATCH -H 'Content-Type: application/json' -d '{"name":"Grand Piano","programBase":1}' "$(base)/instruments/$IID" | grep -q '^204$'

echo "[editor-e2e] Proposals composeBlock + accept…"
P_CREATE='{"op":"composeBlock","params":{"text":"World"},"anchor":"act1.scene1"}'
P_RESP=$(curl -sS -H 'Content-Type: application/json' -d "$P_CREATE" "$(base)/proposals")
PID=$(printf '%s' "$P_RESP" | sed -n 's/.*"proposalId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
[[ -n "$PID" ]] || { echo "[editor-e2e] proposalId missing" >&2; echo "$P_RESP"; exit 7; }

DEC='{"decision":"accept"}'
R=$(curl -sS -H 'Content-Type: application/json' -d "$DEC" "$(base)/proposals/$PID")
APPLIED=$(printf '%s' "$R" | sed -n 's/.*"applied"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p')
[[ "$APPLIED" == "true" ]] || { echo "[editor-e2e] proposal not applied" >&2; echo "$R"; exit 8; }

echo "[editor-e2e] Verify script content…"
BODY=$(curl -sS "$(base)/script")
grep -q 'Hello' <<< "$BODY"
grep -q 'World' <<< "$BODY"

echo "[editor-e2e] OK"

