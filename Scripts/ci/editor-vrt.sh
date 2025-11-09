#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PKG_PATH="$ROOT_DIR/Packages/FountainApps"

echo "[editor-vrt] Generating/validating Fountain Editor snapshots…"

# Ensure prompt is seeded (fail-fast)
swift run --package-path "$PKG_PATH" -c debug fountain-editor-seed

# Update baselines when requested
if [[ "${UPDATE_BASELINES:-0}" == "1" ]]; then
  swift run --package-path "$PKG_PATH" -c debug editor-snapshots --update
  echo "[editor-vrt] Baselines updated. Commit them as part of the change."
  exit 0
fi

# Validate against baselines (non-zero exit on drift)
swift run --package-path "$PKG_PATH" -c debug editor-snapshots

echo "[editor-vrt] Snapshots match baselines."

