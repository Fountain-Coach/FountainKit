#!/usr/bin/env bash
set -euo pipefail

# mvk-runtime-smoke.sh — Fast E2E smoke for MetalViewKit runtime
#
# Usage:
#   bash Scripts/ci/mvk-runtime-smoke.sh [--package-path Packages/FountainApps]
#
# Behavior:
# - Builds and runs the standalone mvk-runtime-tests executable.
# - Writes JSON summary under .fountain/logs with timestamp.
# - Exits non-zero if the smoke fails or summary does not indicate ok:true.

PKG_PATH="Packages/FountainApps"
if [[ "${1:-}" == "--package-path" ]]; then
  PKG_PATH="${2:-Packages/FountainApps}"
fi

LOG_ROOT=".fountain/logs"
mkdir -p "$LOG_ROOT"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_JSON="$LOG_ROOT/mvk-runtime-smoke-$STAMP.json"

echo "[mvk-runtime-smoke] Building mvk-runtime-tests (package: $PKG_PATH)" >&2
swift build --package-path "$PKG_PATH" -c debug --target mvk-runtime-tests >/dev/null

echo "[mvk-runtime-smoke] Running mvk-runtime-tests" >&2
if ! swift run --package-path "$PKG_PATH" mvk-runtime-tests | tee "$OUT_JSON"; then
  echo "[mvk-runtime-smoke] mvk-runtime-tests failed (see $OUT_JSON)" >&2
  exit 2
fi

# Minimal parse without jq: look for '"ok": true'
if ! grep -q '"ok"[[:space:]]*:[[:space:]]*true' "$OUT_JSON"; then
  echo "[mvk-runtime-smoke] Summary did not indicate ok:true (see $OUT_JSON)" >&2
  exit 3
fi

echo "[mvk-runtime-smoke] OK (summary: $OUT_JSON)" >&2
