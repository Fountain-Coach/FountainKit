#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

if [[ ! -d "$ROOT_DIR/External/SDLKit" || -z "$(ls -A "$ROOT_DIR/External/SDLKit" 2>/dev/null || true)" ]]; then
  echo "[sdlkit-demo] SDLKit submodule not present. Run:" >&2
  echo "  git submodule update --init --recursive External/SDLKit" >&2
  exit 2
fi

if [[ "$(uname)" == "Darwin" ]]; then
  export SDL_VIDEODRIVER="cocoa"
  export SDL_AUDIODRIVER="dummy"
  export SDL_RENDER_DRIVER="metal"
  export SDLKIT_LOG_LEVEL="debug"
  HB_PREFIX="${HOMEBREW_PREFIX:-/opt/homebrew}"
  export DYLD_FALLBACK_LIBRARY_PATH="$HB_PREFIX/lib:${DYLD_FALLBACK_LIBRARY_PATH:-}"
  export DYLD_LIBRARY_PATH="$HB_PREFIX/lib:${DYLD_LIBRARY_PATH:-}"
  export SDLKIT_GUI_ENABLED=1
  export SDLKIT_RENDER_BACKEND=metal
  export SDLKIT_FORCE_SYSTEM_SDL=1
  export SDL3_INCLUDE_DIR="${SDL3_INCLUDE_DIR:-$HB_PREFIX/include}"
  export SDL3_LIB_DIR="${SDL3_LIB_DIR:-$HB_PREFIX/lib}"
fi

echo "[sdlkit-demo] Building…"
swift build --package-path "$ROOT_DIR/External/SDLKit" -c debug

echo "[sdlkit-demo] Running SDLKitDemo…"
if ! swift run --package-path "$ROOT_DIR/External/SDLKit" SDLKitDemo; then
  echo "[sdlkit-demo] Demo reported an error; retrying with legacy 2D renderer…"
  SDLKIT_DEMO_FORCE_2D=1 swift run --package-path "$ROOT_DIR/External/SDLKit" SDLKitDemo
fi
