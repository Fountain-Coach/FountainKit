#!/usr/bin/env bash
set -euo pipefail

# Register the instrument-new OpenAPI as ToolsFactory functions.
#
# Usage:
#   Scripts/openapi/register-instrument-new-as-tools.sh \
#     --tools-factory http://127.0.0.1:8011 \
#     --corpus instruments
#
# Defaults:
#   TOOLS_FACTORY_URL = http://127.0.0.1:8011
#   CORPUS_ID         = instruments
#

ROOT_DIR=$(cd "$(dirname "$0")/../.." && pwd)
SPEC_PATH="$ROOT_DIR/Packages/FountainSpecCuration/openapi/v1/instrument-new.yml"
TOOLS_FACTORY_URL="http://127.0.0.1:8011"
CORPUS_ID="instruments"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tools-factory) TOOLS_FACTORY_URL="$2"; shift 2 ;;
    --corpus) CORPUS_ID="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--tools-factory URL] [--corpus ID]" ; exit 0 ;;
    *) echo "Unknown arg: $1" >&2 ; exit 2 ;;
  esac
done

ART_DIR="$ROOT_DIR/.fountain/artifacts"
mkdir -p "$ART_DIR"
TMP_JSON="$ART_DIR/instrument-new.openapi.json"

echo "[instrument-new-register] Normalizing OpenAPI → JSON…"
swift run --package-path "$ROOT_DIR/Packages/FountainTooling" -c debug openapi-jsonify --spec "$SPEC_PATH" > "$TMP_JSON"

QUERY="corpusId=$CORPUS_ID"

echo "[instrument-new-register] Registering with ToolsFactory at $TOOLS_FACTORY_URL"
curl -fsSL -X POST -H 'Content-Type: application/json' \
  --data-binary @"$TMP_JSON" \
  "$TOOLS_FACTORY_URL/tools/register?$QUERY"

echo
echo "[instrument-new-register] Done. List tools with: curl -fsSL '$TOOLS_FACTORY_URL/tools?page=1&page_size=100' | jq ."

