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
  "audiotalk.yml:fountain.coach/agent/audiotalk/service"
  "auth-gateway.yml:fountain.coach/agent/auth-gateway/service"
  "baseline-awareness.yml:fountain.coach/agent/baseline-awareness/service"
  "bootstrap.yml:fountain.coach/agent/bootstrap/service"
  "budget-breaker-gateway.yml:fountain.coach/agent/budget-breaker-gateway/service"
  "chatkit-gateway.yml:fountain.coach/agent/chatkit-gateway/service"
  "curator-gateway.yml:fountain.coach/agent/curator-gateway/service"
  "destructive-guardian-gateway.yml:fountain.coach/agent/destructive-guardian-gateway/service"
  "dns.yml:fountain.coach/agent/dns/service"
  "fk-ops.yml:fountain.coach/agent/fk-ops/service"
  "fountain-editor.yml:fountain.coach/agent/fountain-editor/service"
  "function-caller.yml:fountain.coach/agent/function-caller/service"
  "gateway.yml:fountain.coach/agent/gateway/service"
  "llm-gateway.yml:fountain.coach/agent/llm-gateway/service"
  "metalviewkit-runtime.yml:fountain.coach/agent/metalviewkit-runtime/service"
  "metalviewkit-runtime.yml:fountain.coach/agent/fountain-gui-demo/service"
  "midi-service.yml:fountain.coach/agent/midi-service/service"
  "instrument-lint.yml:fountain.coach/agent/instrument-lint/service"
  "openapi-curator.yml:fountain.coach/agent/openapi-curator/service"
  "patchbay.yml:fountain.coach/agent/patchbay/service"
  "payload-inspection-gateway.yml:fountain.coach/agent/payload-inspection-gateway/service"
  "pb-vrt.yml:fountain.coach/agent/pb-vrt/service"
  "mpe-pad.yml:fountain.coach/agent/mpe-pad/service"
  "planner.yml:fountain.coach/agent/planner/service"
  "persist.yml:fountain.coach/agent/persist/service"
  "quietframe.yml:fountain.coach/agent/quietframe/service"
  "rate-limiter-gateway.yml:fountain.coach/agent/rate-limiter-gateway/service"
  "role-health-check-gateway.yml:fountain.coach/agent/role-health-check-gateway/service"
  "security-sentinel-gateway.yml:fountain.coach/agent/security-sentinel-gateway/service"
  "semantic-browser.yml:fountain.coach/agent/semantic-browser/service"
  "the-four-stars-speech-atlas.yml:fountain.coach/agent/the-four-stars-speech-atlas/service"
  "tool-server.yml:fountain.coach/agent/tool-server/service"
  "tools-factory.yml:fountain.coach/agent/tools-factory/service"
  "qc-mock.yaml:fountain.coach/agent/qc-mock/service"
  "composer-score.yml:fountain.coach/agent/composer-score/service"
  "composer-script.yml:fountain.coach/agent/composer-script/service"
  "composer-cues.yml:fountain.coach/agent/composer-cues/service"
  "fountain-gui-demo.yml:fountain.coach/agent/fountain-gui-demo/service"
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
    swift run --package-path "$TOOL_PKG" -c debug openapi-to-facts "$SPEC_PATH" --agent-id "$AGENT_ID" --seed --allow-tools-only >/dev/null
done

echo "[openapi-to-facts] ✅ done"
