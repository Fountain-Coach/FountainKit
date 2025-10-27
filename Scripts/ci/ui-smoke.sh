#!/usr/bin/env bash
set -euo pipefail

# PatchBay UI smoke — render snapshots via the app and RMSE-compare against baselines

ROOT_DIR=$(cd "$(dirname "$0")/../.." && pwd)
PKG_PATH="$ROOT_DIR/Packages/FountainApps"
ART_DIR="$ROOT_DIR/.fountain/artifacts"
BASE_DIR="$ROOT_DIR/Packages/FountainApps/Tests/PatchBayAppUITests/Baselines"
mkdir -p "$ART_DIR"

echo "[ui-smoke] building patchbay-app + img-rmse"
swift build --package-path "$PKG_PATH" -c debug --target patchbay-app >/dev/null
swift build --package-path "$PKG_PATH" -c debug --target img-rmse >/dev/null

echo "[ui-smoke] rendering current snapshots via app"
PATCHBAY_WRITE_BASELINES=1 swift run --package-path "$PKG_PATH" -c debug patchbay-app >/dev/null

fail=0
check() {
  local name="$1"; shift
  local base="$1"; shift
  local cand="$1"; shift
  local thr="$1"; shift
  if [[ ! -f "$base" ]]; then
    echo "[ui-smoke] MISSING baseline: $base" >&2
    fail=1
    return
  fi
  if [[ ! -f "$cand" ]]; then
    echo "[ui-smoke] MISSING candidate: $cand (render step failed?)" >&2
    fail=1
    return
  fi
  echo "[ui-smoke] compare $name (threshold=$thr)"
  set +e
  swift run --package-path "$PKG_PATH" -c debug img-rmse -t "$thr" "$base" "$cand" --heatmap "$ART_DIR/${name}.heatmap.tiff"
  rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    echo "[ui-smoke] FAIL: $name exceeds threshold (see $ART_DIR)" >&2
    fail=1
  fi
}

check initial-open \
  "$BASE_DIR/initial-open.tiff" \
  "$ART_DIR/patchbay-initial-open.tiff" \
  5.0

check initial-open-1280x800-portrait \
  "$BASE_DIR/initial-open-1280x800-portrait.tiff" \
  "$ART_DIR/patchbay-initial-open-1280x800-portrait.tiff" \
  5.0

check basic-canvas \
  "$BASE_DIR/basic-canvas.tiff" \
  "$ART_DIR/patchbay-basic-canvas.tiff" \
  2.0

if [[ $fail -ne 0 ]]; then
  echo "[ui-smoke] One or more checks failed. To rebaseline intentionally changed visuals, run:"
  echo "  bash Scripts/ci/ui-rebaseline.sh"
  exit 2
fi

echo "[ui-smoke] OK"
