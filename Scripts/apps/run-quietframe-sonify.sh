#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CFG="${1:-debug}"
export CLANG_MODULE_CACHE_PATH="$ROOT/.fountain/clang-module-cache"
export SWIFTPM_ENABLE_SANDBOX=0
# Tell QuietFrame to use the MVK runtime sidecar loopback transport unless overridden
export QF_USE_RUNTIME="${QF_USE_RUNTIME:-1}"
export QF_TRANSPORT="${QF_TRANSPORT:-}"
export FK_MIDI_DISABLE_INPUT="${FK_MIDI_DISABLE_INPUT:-}"

# Allow caller to prebuild and skip here (to avoid overlapping SwiftPM invocations)
if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  swift build --disable-sandbox --package-path "$ROOT/Packages/FountainApps" -c "$CFG" --target quietframe-sonify-app
fi
BIN="$(swift build --disable-sandbox --package-path "$ROOT/Packages/FountainApps" -c "$CFG" --show-bin-path)"
APP="$BIN/quietframe-sonify-app"
APP_BUNDLE="$BIN/quietframe-sonify-app.app"
if [[ -x "$APP" ]]; then exec env QF_USE_RUNTIME="$QF_USE_RUNTIME" QF_TRANSPORT="$QF_TRANSPORT" FK_MIDI_DISABLE_INPUT="$FK_MIDI_DISABLE_INPUT" "$APP"; fi
if [[ -d "$APP_BUNDLE" ]]; then
  open "$APP_BUNDLE" && \
  osascript -e 'tell application "QuietFrame Sonify" to activate' >/dev/null 2>&1 || true
  exit 0
fi
# Fallback: search under .build for a matching product
PROD="$(
  find "$ROOT/Packages/FountainApps/.build" -type f -name 'quietframe*sonify*' -print 2>/dev/null | head -n 1
)"
if [[ -n "${PROD:-}" && -x "$PROD" ]]; then exec "$PROD"; fi
APP_DIR="$(
  find "$ROOT/Packages/FountainApps/.build" -type d -name 'quietframe*sonify*.app' -print 2>/dev/null | head -n 1
)"
if [[ -n "${APP_DIR:-}" && -d "$APP_DIR" ]]; then
  open "$APP_DIR" && \
  osascript -e 'tell application "QuietFrame Sonify" to activate' >/dev/null 2>&1 || true
  exit 0
fi
echo "[quietframe-sonify] built, but product not found under $BIN" 1>&2
# Final fallback: swift run directly (no sandbox) — still respects QF_USE_RUNTIME
exec env CLANG_MODULE_CACHE_PATH="$CLANG_MODULE_CACHE_PATH" SWIFTPM_ENABLE_SANDBOX=0 QF_USE_RUNTIME="$QF_USE_RUNTIME" QF_TRANSPORT="$QF_TRANSPORT" FK_MIDI_DISABLE_INPUT="$FK_MIDI_DISABLE_INPUT" \
  swift run --disable-sandbox --package-path "$ROOT/Packages/FountainApps" -c "$CFG" quietframe-sonify-app
