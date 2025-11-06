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
if [[ -x "$APP" ]]; then exec "$APP"; fi
if [[ -d "$APP_BUNDLE" ]]; then open "$APP_BUNDLE" && exit 0; fi
PROD="$(
  find "$ROOT/Packages/FountainApps/.build" -type f -maxdepth 3 -perm +111 -name 'quietframe*companion*' -print 2>/dev/null | head -n 1
)"
if [[ -n "${PROD:-}" && -x "$PROD" ]]; then exec "$PROD"; fi
APP_DIR="$(
  find "$ROOT/Packages/FountainApps/.build" -type d -maxdepth 3 -name 'quietframe*companion*.app' -print 2>/dev/null | head -n 1
)"
if [[ -n "${APP_DIR:-}" && -d "$APP_DIR" ]]; then open "$APP_DIR" && exit 0; fi
echo "[quietframe-companion] built, but product not found under $BIN" 1>&2
exit 1
