#!/usr/bin/env bash
set -euo pipefail

# Visual regression checks for PatchBay UI. Runs target-scoped tests and gathers artifacts.

ROOT_DIR=$(cd "$(dirname "$0")/../.." && pwd)
ART_DIR="$ROOT_DIR/.fountain/artifacts"
mkdir -p "$ART_DIR"

echo "[vrt] building app + UI tests"
swift build --package-path "$ROOT_DIR/Packages/FountainApps" -c debug --target patchbay-app >/dev/null
swift build --package-path "$ROOT_DIR/Packages/FountainApps" -c debug --target PatchBayAppUITests >/dev/null

echo "[vrt] running UI snapshot tests"
set +e
swift test --package-path "$ROOT_DIR/Packages/FountainApps" -c debug --filter PatchBayAppUITests
RC=$?
set -e

echo "[vrt] artifacts: $ART_DIR"
ls -la "$ART_DIR" || true

exit $RC

