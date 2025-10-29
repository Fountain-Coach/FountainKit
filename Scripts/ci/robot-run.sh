#!/usr/bin/env bash
set -euo pipefail
# robot-run.sh — run robot + replay tests locally and open failure artifacts
# Usage: Scripts/ci/robot-run.sh

ROOT_DIR=$(cd "$(dirname "$0")/../.." && pwd)
pushd "$ROOT_DIR" >/dev/null

echo "[robot] running PatchBayAppUITests (robot + replay + invariants)"
swift test --package-path Packages/FountainApps -c debug --filter PatchBayAppUITests || true

# Open newest replay artifact folder if any .mov exists
ART="$ROOT_DIR/.fountain/artifacts/replay"
if [ -d "$ART" ]; then
  MOV=$(find "$ART" -name "*.mov" -type f -print0 | xargs -0 ls -t | head -n 1 || true)
  if [ -n "${MOV:-}" ]; then
    echo "[robot] opening replay artifact: $MOV"
    open -R "$MOV" || true
  fi
fi

popd >/dev/null
echo "[robot] done"

