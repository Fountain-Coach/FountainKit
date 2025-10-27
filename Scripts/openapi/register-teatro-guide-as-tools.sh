#!/usr/bin/env bash
set -euo pipefail

# Register the Teatro Prompt Field Guide OpenAPI as ToolsFactory functions.
#
# Usage:
#   Scripts/openapi/register-teatro-guide-as-tools.sh \
#     --spec https://raw.githubusercontent.com/Fountain-Coach/teatro-codex-macos-prompt-field-guide/main/openapi.yaml \
#     --tools-factory http://127.0.0.1:8011 \
#     --corpus teatro-guide \
#     --base https://teatro-guide.local

ROOT_DIR=$(cd "$(dirname "$0")/../.." && pwd)
SPEC_URL="https://raw.githubusercontent.com/Fountain-Coach/teatro-codex-macos-prompt-field-guide/main/openapi.yaml"
TOOLS_FACTORY_URL="http://127.0.0.1:8011"
CORPUS_ID="teatro-guide"
BASE_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --spec) SPEC_URL="$2"; shift 2 ;;
    --tools-factory) TOOLS_FACTORY_URL="$2"; shift 2 ;;
    --corpus) CORPUS_ID="$2"; shift 2 ;;
    --base) BASE_OVERRIDE="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--spec openapi.(yaml|json)] [--tools-factory URL] [--corpus ID] [--base URL]" ; exit 0 ;;
    *) echo "Unknown arg: $1" >&2 ; exit 2 ;;
  esac
done

ART_DIR="$ROOT_DIR/.fountain/artifacts"
mkdir -p "$ART_DIR"
TMP_JSON="$ART_DIR/teatro-guide.openapi.json"

echo "[register] Fetching and normalizing OpenAPI → JSON…"
swift run --package-path "$ROOT_DIR/Packages/FountainTooling" -c debug openapi-jsonify --spec "$SPEC_URL" > "$TMP_JSON"

QUERY="corpusId=$CORPUS_ID"

# If a base override is provided, inject it as servers[0].url into the JSON
if [[ -n "$BASE_OVERRIDE" ]]; then
  echo "[register] Injecting base URL into OpenAPI servers: $BASE_OVERRIDE"
  python3 - "$TMP_JSON" "$BASE_OVERRIDE" <<'PY'
import sys, json
path, base = sys.argv[1], sys.argv[2]
with open(path, 'rb') as f:
    obj = json.load(f)
obj['servers'] = [{ 'url': base }]
with open(path, 'w') as f:
    json.dump(obj, f)
PY
fi

echo "[register] Registering with ToolsFactory at $TOOLS_FACTORY_URL…"
curl -fsSL -X POST -H 'Content-Type: application/json' \
  --data-binary @"$TMP_JSON" \
  "$TOOLS_FACTORY_URL/tools/register?$QUERY"

echo
echo "[register] Done. List tools with: curl -fsSL '$TOOLS_FACTORY_URL/tools?page=1&page_size=100' | jq ."
