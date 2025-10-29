#!/usr/bin/env bash
set -euo pipefail
# robot-only.sh — run ONLY PatchBayAppUITests (robot + replay + invariants)
# Usage: Scripts/tests/robot-only.sh [--open]

ROOT_DIR=$(cd "$(dirname "$0")/../.." && pwd)
pushd "$ROOT_DIR" >/dev/null

FILTER='^PatchBayAppUITests\.'
echo "[robot-only] running PatchBayAppUITests with filter $FILTER"
swift test --package-path Packages/FountainApps -c debug --filter "$FILTER" --quiet || true

if [[ ":${*}:" == *:"--open":* ]]; then
  ART="$ROOT_DIR/.fountain/artifacts/replay"
  if [ -d "$ART" ]; then
    MOV=$(find "$ART" -name "*.mov" -type f -print0 | xargs -0 ls -t 2>/dev/null | head -n 1 || true)
    if [ -n "${MOV:-}" ]; then
      echo "[robot-only] opening replay artifact: $MOV"
      open -R "$MOV" || true
    fi
  fi
fi

popd >/dev/null
echo "[robot-only] done"

