#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CFG="${1:-debug}"
export CLANG_MODULE_CACHE_PATH="$ROOT/.fountain/clang-module-cache"
export SWIFTPM_ENABLE_SANDBOX=0
swift build --package-path "$ROOT/Packages/FountainApps" -c "$CFG" --target quietframe-companion-app
BIN="$(swift build --package-path "$ROOT/Packages/FountainApps" -c "$CFG" --show-bin-path)"
APP="$BIN/quietframe-companion-app"
APP_BUNDLE="$BIN/quietframe-companion-app.app"
if [[ -x "$APP" ]]; then
  exec "$APP"
elif [[ -d "$APP_BUNDLE" ]]; then
  open "$APP_BUNDLE" && exit 0
else
  echo "[quietframe-companion] built, but product not found under $BIN" 1>&2
  echo "Contents:" 1>&2
  ls -la "$BIN" 1>&2
  exit 1
fi
