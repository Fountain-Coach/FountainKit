#!/usr/bin/env bash
set -euo pipefail

# Seed a minimal PatchBay scene as described in the DSL prompt:
# - Add an audiotalk.chat instrument at x=320,y=180,w=240,h=120 (id=chat1)
# - Link UMP CC7 (CoreMIDI in, group 0, channel 1) → chat1.inputGain with linear 0.5 scale
# - Save graph under id=demo-chat
# - Emit a corpus snapshot
#
# Usage:
#   Scripts/apps/patchbay-seed-demo-chat.sh [--base-url http://127.0.0.1:7090]

BASE_URL="${PATCHBAY_URL:-http://127.0.0.1:${PATCHBAY_PORT:-7090}}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) BASE_URL="$2"; shift 2 ;;
    -h|--help) echo "Usage: $0 [--base-url URL]"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

http_json() { curl -sf -H 'Accept: application/json' "$@"; }
http_post_json() { curl -sf -X POST -H 'Content-Type: application/json' "$@"; }
http_put_json() { curl -sf -X PUT -H 'Content-Type: application/json' "$@"; }

echo "[seed] Using PatchBay at $BASE_URL"

echo "[seed] Ensuring instrument chat1 (audiotalk.chat) exists…"
EXISTS=$(http_json "$BASE_URL/instruments" | python3 - <<'PY'
import sys, json
arr=json.load(sys.stdin)
print('yes' if any(x.get('id')=='chat1' for x in arr) else 'no')
PY
)
if [[ "$EXISTS" != "yes" ]]; then
  BODY=$(cat <<JSON
{"id":"chat1","kind":"audiotalk.chat","title":"Chat","x":320,"y":180,"w":240,"h":120}
JSON
)
  http_post_json "$BASE_URL/instruments" --data "$BODY" >/dev/null
  echo "[seed] Created instrument chat1"
else
  echo "[seed] Instrument chat1 already present"
fi

echo "[seed] Ensuring one UMP CC7→chat1.inputGain link exists…"
LINKS=$(http_json "$BASE_URL/links")
HAS=$(echo "$LINKS" | python3 - <<'PY'
import sys, json
arr=json.load(sys.stdin)
def prop_to_to(l):
    p=l.get('property') or {}
    return p.get('to')
def ump_to_to(l):
    u=l.get('ump') or {}
    return u.get('to')
print('yes' if any((prop_to_to(l)=='chat1.inputGain') or (ump_to_to(l)=='chat1.inputGain') for l in arr) else 'no')
PY
)
if [[ "$HAS" != "yes" ]]; then
  BODY=$(cat <<'JSON'
{
  "kind": "ump",
  "ump": {
    "source": { "endpointId": "coremidi.in", "group": 0, "channel": 1, "message": "cc", "cc": 7 },
    "to": "chat1.inputGain",
    "map": { "curve": "linear", "scale": 0.5, "offset": 0.0 }
  }
}
JSON
)
  http_post_json "$BASE_URL/links" --data "$BODY" >/dev/null
  echo "[seed] Created UMP link CC7→chat1.inputGain"
else
  echo "[seed] UMP link to chat1.inputGain already present"
fi

echo "[seed] Saving current graph as demo-chat…"
GRAPH=$(http_json "$BASE_URL/graph")
PUT=$(python3 - <<PY "$GRAPH"
import sys, json
doc=json.loads(sys.argv[1])
sg={'id':'demo-chat','doc':doc}
print(json.dumps(sg))
PY
)
http_put_json "$BASE_URL/store/graphs/demo-chat" --data "$PUT" >/dev/null
echo "[seed] Saved store/graphs/demo-chat"

echo "[seed] Emitting corpus snapshot…"
SNAP=$(http_post_json "$BASE_URL/corpus/snapshot" --data '{"includeSchemas":true,"includeMappings":true}')
echo "$SNAP" | (head -c 256; echo "…") || true
echo "[seed] Done"

