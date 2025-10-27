#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/../.." && pwd)
ART_DIR="$ROOT_DIR/.fountain/artifacts"
BASE_DIR="$ROOT_DIR/Packages/FountainApps/Tests/PatchBayAppUITests/Baselines"
mkdir -p "$ART_DIR" "$BASE_DIR"

echo "[vrt] building patchbay-app"
swift build --package-path "$ROOT_DIR/Packages/FountainApps" -c debug --target patchbay-app >/dev/null

echo "[vrt] generating candidates by running app snapshot writer"
PATCHBAY_WRITE_BASELINES=1 swift run --package-path "$ROOT_DIR/Packages/FountainApps" -c debug patchbay-app >/dev/null

echo "[vrt] copying generated candidates to baselines"
shopt -s nullglob
for f in "$ART_DIR"/patchbay-*.tiff "$ART_DIR"/patchbay-initial-open.tiff "$ART_DIR"/patchbay-basic-canvas.tiff; do
  base=$(basename "$f")
  case "$base" in
    patchbay-initial-open.tiff) cp "$f" "$BASE_DIR/initial-open.tiff" ;;
    patchbay-basic-canvas.tiff) cp "$f" "$BASE_DIR/basic-canvas.tiff" ;;
    patchbay-initial-open-1280x800-portrait.tiff) cp "$f" "$BASE_DIR/initial-open-1280x800-portrait.tiff" ;;
    *) echo "[vrt] ignoring $base" ;;
  esac
done
echo "[vrt] baselines now in $BASE_DIR"
