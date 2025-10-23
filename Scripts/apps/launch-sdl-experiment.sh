#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

if [[ ! -d "$ROOT_DIR/External/SDLKit" || -z "$(ls -A "$ROOT_DIR/External/SDLKit" 2>/dev/null || true)" ]]; then
  echo "[sdl-experiment] SDLKit submodule not present. Run:" >&2
  echo "  git submodule update --init --recursive External/SDLKit" >&2
  exit 2
fi

# Check SDL3 runtime libs (macOS): libSDL3*.dylib should exist under Homebrew prefix
if [[ "$(uname)" == "Darwin" ]]; then
  HB_PREFIX="${HOMEBREW_PREFIX:-/opt/homebrew}"
  if [[ ! -f "$HB_PREFIX/lib/libSDL3.dylib" ]]; then
    echo "[sdl-experiment] SDL3 runtime not found at $HB_PREFIX/lib/libSDL3.dylib" >&2
    echo "Install dependencies (one-time):" >&2
    echo "  brew install sdl3 sdl3_ttf sdl3_image" >&2
    echo "Or run: AUTO_INSTALL_SDL_DEPS=1 $0" >&2
    if [[ "${AUTO_INSTALL_SDL_DEPS:-0}" == "1" ]]; then
      if ! command -v brew >/dev/null 2>&1; then
        echo "[sdl-experiment] Homebrew not found; install from https://brew.sh first." >&2
        exit 2
      fi
      echo "[sdl-experiment] Installing SDL3 deps via Homebrew…"
      brew install sdl3 sdl3_ttf sdl3_image
    else
      exit 2
    fi
  fi
fi

echo "[sdl-experiment] Building…"
swift build --package-path "$ROOT_DIR/Packages/SDLExperiment" -c debug

echo "[sdl-experiment] Running…"
# Hint common SDL runtime env on macOS
if [[ "$(uname)" == "Darwin" ]]; then
  export SDL_VIDEODRIVER="cocoa"
  # Use dummy audio to avoid device errors on some setups
  export SDL_AUDIODRIVER="dummy"
  # Help the dynamic loader find Homebrew libraries
  HB_PREFIX="${HOMEBREW_PREFIX:-/opt/homebrew}"
  export DYLD_FALLBACK_LIBRARY_PATH="$HB_PREFIX/lib:${DYLD_FALLBACK_LIBRARY_PATH:-}"
  # Some setups honor DYLD_LIBRARY_PATH over the fallback path
  export DYLD_LIBRARY_PATH="$HB_PREFIX/lib:${DYLD_LIBRARY_PATH:-}"
  # SDLKit runtime hints
  export SDLKIT_GUI_ENABLED=1
  export SDLKIT_PRESENT_POLICY=auto
  export SDLKIT_RENDER_BACKEND=metal
  # Force SDLKit to link against system SDL3 if pkg-config is not set up
  export SDLKIT_FORCE_SYSTEM_SDL=1
  export SDL3_INCLUDE_DIR="${SDL3_INCLUDE_DIR:-$HB_PREFIX/include}"
  export SDL3_LIB_DIR="${SDL3_LIB_DIR:-$HB_PREFIX/lib}"
fi
swift run --package-path "$ROOT_DIR/Packages/SDLExperiment" sdl-composer-experiment
status=$?
if [[ $status -ne 0 ]]; then
  echo "[sdl-experiment] Experiment returned non-zero; running diagnostics…" >&2
  swift run --package-path "$ROOT_DIR/Packages/SDLExperiment" sdl-diagnostics || true
fi
