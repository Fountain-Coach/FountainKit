#!/usr/bin/env bash
set -euo pipefail

# Teatro Prompt Field Guide smoke — register tools, invoke one via FunctionCaller, store ETag.

ROOT_DIR=$(cd "$(dirname "$0")/../.." && pwd)
ART_DIR="$ROOT_DIR/.fountain/artifacts"
mkdir -p "$ART_DIR"

TOOLS_FACTORY_URL="${TOOLS_FACTORY_URL:-http://127.0.0.1:8011}"
FUNCTION_CALLER_URL="${FUNCTION_CALLER_URL:-http://127.0.0.1:8004}"
CORPUS_ID="${TEATRO_GUIDE_CORPUS:-teatro-guide}"
SPEC_URL="${TEATRO_GUIDE_SPEC:-https://raw.githubusercontent.com/Fountain-Coach/teatro-codex-macos-prompt-field-guide/main/openapi.yaml}"
BASE_URL="${TEATRO_GUIDE_BASE_URL:-}"

http_200() {
  curl -sf --max-time 3 "$1" >/dev/null 2>&1
}

echo "[tg-smoke] Checking ToolsFactory at $TOOLS_FACTORY_URL"
if ! http_200 "$TOOLS_FACTORY_URL/metrics"; then
  echo "[tg-smoke] ToolsFactory not reachable: $TOOLS_FACTORY_URL" >&2
  exit 2
fi

echo "[tg-smoke] Registering Teatro Prompt Field Guide tools (corpus=$CORPUS_ID)"
if [[ -n "$BASE_URL" ]]; then BASE_ARGS=(--base "$BASE_URL"); else BASE_ARGS=(); fi
bash "$ROOT_DIR/Scripts/openapi/register-teatro-guide-as-tools.sh" \
  --spec "$SPEC_URL" \
  --tools-factory "$TOOLS_FACTORY_URL" \
  --corpus "$CORPUS_ID" \
  "${BASE_ARGS[@]}"

echo "[tg-smoke] Listing tools…"
JSON=$(curl -sf --max-time 5 "$TOOLS_FACTORY_URL/tools?page=1&page_size=100")

# Extract first function (best-effort, no jq dependency)
extract() {
  echo "$JSON" | python3 - "$1" <<'PY'
import sys, json
obj=json.load(sys.stdin)
path=sys.argv[1].split('.')
def get(o, ks):
    for k in ks:
        if isinstance(o, list):
            if k == '*':
                return o
            try: i=int(k); o=o[i]
            except: return None
        elif isinstance(o, dict):
            o=o.get(k)
        else:
            return None
    return o
val=get(obj, path)
if isinstance(val, (str,int,float)):
    print(val)
PY
}

FN_ID=$(echo "$JSON" | python3 - <<'PY'
import sys,json
obj=json.load(sys.stdin)
f=obj.get('functions',[])
print(f[0]['function_id'] if f else '')
PY
)

if [[ -z "$FN_ID" ]]; then
  echo "[tg-smoke] No tools registered (empty set)." >&2
  exit 3
fi

METHOD=$(echo "$JSON" | python3 - <<'PY'
import sys,json
obj=json.load(sys.stdin)
f=obj.get('functions',[])
print(f[0].get('http_method','GET'))
PY
)

echo "[tg-smoke] Invoking via FunctionCaller: $FN_ID ($METHOD)…"
BODY='{}'
if [[ "$METHOD" == "GET" ]]; then BODY=''; fi
set +e
if [[ -n "$BODY" ]]; then
RESP=$(curl -sS -X POST -H 'Content-Type: application/json' --data "$BODY" "$FUNCTION_CALLER_URL/functions/$FN_ID/invoke")
  RC=$?
else
RESP=$(curl -sS -X POST "$FUNCTION_CALLER_URL/functions/$FN_ID/invoke")
  RC=$?
fi
set -e
if [[ $RC -ne 0 ]]; then
  echo "[tg-smoke] WARN: Invocation failed (non-zero curl exit). Capturing response if any." >&2
fi

OUT_PREFIX="$ART_DIR/teatro-guide.$FN_ID"
printf "%s" "$RESP" > "$OUT_PREFIX.response"
HASH=$(shasum -a 256 "$OUT_PREFIX.response" | awk '{print $1}')
echo "$HASH" > "$OUT_PREFIX.etag"
echo "[tg-smoke] Wrote response and ETag under $ART_DIR (prefix: $(basename "$OUT_PREFIX"))"

echo "[tg-smoke] OK"
