#!/usr/bin/env bash
set -euo pipefail

# Generate aggregated agent-facts for the Composer Studio agent from
# composer-specific and shared specs (score, script, cues, awareness,
# planner, function-caller, tools-factory).
#
# Usage: Scripts/openapi/openapi-to-facts-composer.sh
# Env:
#   FOUNTAINSTORE_DIR (optional) — defaults to .fountain/store
#   CORPUS_ID (optional)        — defaults to "agents"
#   AGENT_ID (optional)         — defaults to fountain.coach/agent/composer-studio/service

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL_PKG="$ROOT_DIR/Packages/FountainTooling"
SPECS_DIR="$ROOT_DIR/Packages/FountainSpecCuration/openapi/v1"

: "${FOUNTAINSTORE_DIR:=$ROOT_DIR/.fountain/store}"
: "${CORPUS_ID:=agents}"
: "${AGENT_ID:=fountain.coach/agent/composer-studio/service}"

COMPOSER_SPECS=(
  "composer-score.yml"
  "composer-script.yml"
  "composer-cues.yml"
)

SHARED_SPECS=(
  "baseline-awareness.yml"
  "planner.yml"
  "function-caller.yml"
  "tools-factory.yml"
)

echo "[openapi-to-facts-composer] building tool…"
swift build --package-path "$TOOL_PKG" -c debug --target openapi-to-facts >/dev/null

# Composer services: include all operations as tools (no allow-tools-only filter yet).
for spec in "${COMPOSER_SPECS[@]}"; do
  SPEC_PATH="$SPECS_DIR/$spec"
  if [[ ! -f "$SPEC_PATH" ]]; then
    echo "[openapi-to-facts-composer] WARN: missing spec $SPEC_PATH — skipping"
    continue
  fi
  echo "[openapi-to-facts-composer] seeding from $spec → $AGENT_ID (corpus=$CORPUS_ID)"
  FOUNTAINSTORE_DIR="$FOUNTAINSTORE_DIR" CORPUS_ID="$CORPUS_ID" \
    swift run --package-path "$TOOL_PKG" -c debug openapi-to-facts "$SPEC_PATH" --agent-id "$AGENT_ID" --seed >/dev/null
done

# Shared services: respect per-operation x-fountain.allow-as-tool flags.
for spec in "${SHARED_SPECS[@]}"; do
  SPEC_PATH="$SPECS_DIR/$spec"
  if [[ ! -f "$SPEC_PATH" ]]; then
    echo "[openapi-to-facts-composer] WARN: missing spec $SPEC_PATH — skipping"
    continue
  fi
  echo "[openapi-to-facts-composer] seeding from $spec → $AGENT_ID (corpus=$CORPUS_ID)"
  FOUNTAINSTORE_DIR="$FOUNTAINSTORE_DIR" CORPUS_ID="$CORPUS_ID" \
    swift run --package-path "$TOOL_PKG" -c debug openapi-to-facts "$SPEC_PATH" --agent-id "$AGENT_ID" --seed --allow-tools-only >/dev/null
done

echo "[openapi-to-facts-composer] ✅ composer-studio agent-facts seeded"
