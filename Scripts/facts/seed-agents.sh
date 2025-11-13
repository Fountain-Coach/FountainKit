#!/usr/bin/env bash
set -euo pipefail

# Seeds agent facts into FountainStore from curated OpenAPI specs.
# Usage: Scripts/facts/seed-agents.sh

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL_PKG="$ROOT_DIR/Packages/FountainTooling"
SPEC_DIR="$ROOT_DIR/Packages/FountainSpecCuration/openapi/v1"
STORE_DIR="${FOUNTAINSTORE_DIR:-$ROOT_DIR/.fountain/store}"

# macOS ships bash 3.2 — avoid associative arrays
MAP_LIST=(
  "planner.yml:fountain.coach/agent/planner/service"
  "function-caller.yml:fountain.coach/agent/function-caller/service"
  "persist.yml:fountain.coach/agent/persist/service"
  "baseline-awareness.yml:fountain.coach/agent/baseline-awareness/service"
  "bootstrap.yml:fountain.coach/agent/bootstrap/service"
)

echo "[facts-seed] store=$STORE_DIR"
mkdir -p "$STORE_DIR"
echo "[facts-seed] building generator…"
swift build --package-path "$TOOL_PKG" -c debug --target openapi-to-facts >/dev/null

for item in "${MAP_LIST[@]}"; do
  spec="${item%%:*}"
  agent="${item#*:}"
  path="$SPEC_DIR/$spec"
  if [[ ! -f "$path" ]]; then echo "[facts-seed] WARN: missing $path" >&2; continue; fi
  echo "[facts-seed] $spec → $agent"
  FOUNTAINSTORE_DIR="$STORE_DIR" swift run --package-path "$TOOL_PKG" -c debug openapi-to-facts "$path" --agent-id "$agent" --seed >/dev/null
done
echo "[facts-seed] ✅ done"
