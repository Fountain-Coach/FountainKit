#!/usr/bin/env bash
set -euo pipefail

# Registers AudioTalk OpenAPI operations as tools in the Tools Factory service.

TOOLS_FACTORY_URL=${TOOLS_FACTORY_URL:-http://127.0.0.1:8011}
CORPUS_ID=${TOOLS_CORPUS_ID:-audiotalk}
SPEC_PATH=${SPEC_PATH:-Packages/FountainServiceKit-AudioTalk/Sources/AudioTalkService/openapi.yaml}

if [[ ! -f "$SPEC_PATH" ]]; then
  echo "Spec not found: $SPEC_PATH" >&2
  exit 1
fi

echo "Registering tools for corpus '$CORPUS_ID' from $SPEC_PATH via $TOOLS_FACTORY_URL"

curl -sS -X POST \
  -H "Content-Type: application/json" \
  --data-binary @<(yq -o json "$SPEC_PATH") \
  "$TOOLS_FACTORY_URL/tools/register?corpusId=$CORPUS_ID" | jq -r '.functions[] | "\(.http_method) \(.http_path) => \(.function_id)"'

