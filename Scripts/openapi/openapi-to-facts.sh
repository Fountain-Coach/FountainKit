#!/usr/bin/env bash
set -euo pipefail

# Generate PE facts from curated OpenAPI specs and seed into FountainStore.
# Usage: Scripts/openapi/openapi-to-facts.sh
# Env: FOUNTAINSTORE_DIR (defaults to .fountain/store)

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL_PKG="$ROOT_DIR/Packages/FountainTooling"
SPECS_DIR="$ROOT_DIR/Packages/FountainSpecCuration/openapi/v1"

: "${FOUNTAINSTORE_DIR:=$ROOT_DIR/.fountain/store}"

# macOS ships bash 3.2 — avoid associative arrays
MAP_LIST=(
  "planner.yml:fountain.coach/agent/planner/service"
  "function-caller.yml:fountain.coach/agent/function-caller/service"
  "persist.yml:fountain.coach/agent/persist/service"
  "baseline-awareness.yml:fountain.coach/agent/baseline-awareness/service"
  "bootstrap.yml:fountain.coach/agent/bootstrap/service"
)

echo "[openapi-to-facts] building tool…"
swift build --package-path "$TOOL_PKG" -c debug --target openapi-to-facts >/dev/null

for item in "${MAP_LIST[@]}"; do
  spec="${item%%:*}"
  AGENT_ID="${item#*:}"
  SPEC_PATH="$SPECS_DIR/$spec"
  if [[ ! -f "$SPEC_PATH" ]]; then
    echo "[openapi-to-facts] WARN: missing spec $SPEC_PATH — skipping"
    continue
  fi
  echo "[openapi-to-facts] seeding from $spec → $AGENT_ID"
  FOUNTAINSTORE_DIR="$FOUNTAINSTORE_DIR" \
    swift run --package-path "$TOOL_PKG" -c debug openapi-to-facts "$SPEC_PATH" --agent-id "$AGENT_ID" --seed >/dev/null
done

echo "[openapi-to-facts] ✅ done"
