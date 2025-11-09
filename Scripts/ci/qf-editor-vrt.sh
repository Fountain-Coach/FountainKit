#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PKG_PATH="$ROOT_DIR/Packages/FountainApps"

echo "[qf-editor-vrt] Generating/validating QuietFrame Editor snapshots…"

if [[ "${UPDATE_BASELINES:-0}" == "1" ]]; then
  UPDATE_BASELINES=1 swift test --package-path "$PKG_PATH" -c debug --filter QuietFrameEditorSnapshotTests
  echo "[qf-editor-vrt] Baselines updated. Commit them as part of the change."
  exit 0
fi

swift test --package-path "$PKG_PATH" -c debug --filter QuietFrameEditorSnapshotTests
echo "[qf-editor-vrt] Snapshots match baselines."

