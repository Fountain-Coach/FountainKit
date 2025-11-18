#!/usr/bin/env bash
set -euo pipefail

# Generate PE facts from curated OpenAPI specs and seed into FountainStore.
# Usage: Scripts/openapi/openapi-to-facts.sh
# Env: FOUNTAINSTORE_DIR (defaults to .fountain/store)

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL_PKG="$ROOT_DIR/Packages/FountainTooling"
SPECS_DIR="$ROOT_DIR/Packages/FountainSpecCuration/openapi/v1"
MAP_FILE="$ROOT_DIR/Tools/openapi-facts-mapping.json"

: "${FOUNTAINSTORE_DIR:=$ROOT_DIR/.fountain/store}"

if [[ ! -f "$MAP_FILE" ]]; then
  echo "[openapi-to-facts] ERROR: mapping file $MAP_FILE not found" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "[openapi-to-facts] ERROR: jq is required to read $MAP_FILE" >&2
  exit 1
fi

echo "[openapi-to-facts] building tool…"
swift build --package-path "$TOOL_PKG" -c debug --target openapi-to-facts >/dev/null

while IFS=$'\t' read -r spec AGENT_ID; do
  [[ -z "$spec" || -z "$AGENT_ID" ]] && continue
  SPEC_PATH="$SPECS_DIR/$spec"
  if [[ ! -f "$SPEC_PATH" ]]; then
    echo "[openapi-to-facts] WARN: missing spec $SPEC_PATH — skipping"
    continue
  fi
  echo "[openapi-to-facts] seeding from $spec → $AGENT_ID"
  FOUNTAINSTORE_DIR="$FOUNTAINSTORE_DIR" \
    swift run --package-path "$TOOL_PKG" -c debug openapi-to-facts "$SPEC_PATH" --agent-id "$AGENT_ID" --seed --allow-tools-only >/dev/null
done < <(jq -r '.[] | [.spec, .agentId] | @tsv' "$MAP_FILE")

echo "[openapi-to-facts] ✅ done"
