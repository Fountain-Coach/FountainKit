#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
LOG_DIR="$HOME/.fountain"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/visuals-oneclick.log"

echo "[visuals] Starting one-click visuals run…" | tee "$LOG_FILE"

# Ensure SDLKit submodule
if [[ ! -d "$ROOT_DIR/External/SDLKit/.git" ]]; then
  echo "[visuals] Initializing SDLKit submodule…" | tee -a "$LOG_FILE"
  git -C "$ROOT_DIR" submodule update --init --recursive External/SDLKit | tee -a "$LOG_FILE"
fi

if [[ "$(uname)" == "Darwin" ]]; then
  # Auto-install runtime deps if Homebrew is present
  HB_PREFIX="${HOMEBREW_PREFIX:-/opt/homebrew}"
  if command -v brew >/dev/null 2>&1; then
    if [[ ! -f "$HB_PREFIX/lib/libSDL3.dylib" ]]; then
      echo "[visuals] Installing SDL3 runtime via Homebrew…" | tee -a "$LOG_FILE"
      brew install sdl3 sdl3_image sdl3_ttf | tee -a "$LOG_FILE"
    fi
  fi
  # Runtime env for dynamic loader + SDL
  export SDL_VIDEODRIVER="cocoa"
  export SDL_AUDIODRIVER="dummy"
  export SDL_RENDER_DRIVER="metal"
  export SDLKIT_LOG_LEVEL="debug"
  export DYLD_FALLBACK_LIBRARY_PATH="$HB_PREFIX/lib:${DYLD_FALLBACK_LIBRARY_PATH:-}"
  export DYLD_LIBRARY_PATH="$HB_PREFIX/lib:${DYLD_LIBRARY_PATH:-}"
  export SDLKIT_GUI_ENABLED=1
  export SDLKIT_RENDER_BACKEND=metal
  export SDLKIT_FORCE_SYSTEM_SDL=1
  export SDL3_INCLUDE_DIR="${SDL3_INCLUDE_DIR:-$HB_PREFIX/include}"
  export SDL3_LIB_DIR="${SDL3_LIB_DIR:-$HB_PREFIX/lib}"
fi

echo "[visuals] Building diagnostics + experiment…" | tee -a "$LOG_FILE"
swift build --package-path "$ROOT_DIR/Packages/SDLExperiment" -c debug | tee -a "$LOG_FILE"

echo "[visuals] Running diagnostics…" | tee -a "$LOG_FILE"
if ! swift run --package-path "$ROOT_DIR/Packages/SDLExperiment" sdl-diagnostics | tee -a "$LOG_FILE"; then
  echo "[visuals] Diagnostics failed; continuing to experiment anyway." | tee -a "$LOG_FILE"
fi

echo "[visuals] Running SDL Composer Experiment…" | tee -a "$LOG_FILE"
if ! swift run --package-path "$ROOT_DIR/Packages/SDLExperiment" sdl-composer-experiment | tee -a "$LOG_FILE"; then
  echo "[visuals] Experiment failed; trying SDLKit demo (2D fallback)…" | tee -a "$LOG_FILE"
  # Persist backend override to metal (optional; no-op if tool unavailable)
  if swift run --package-path "$ROOT_DIR/External/SDLKit" SDLKitSettings set --key render.backend.override --value metal >/dev/null 2>&1; then
    echo "[visuals] Set render.backend.override=metal" | tee -a "$LOG_FILE"
  fi
  # Build + run demo with force-2D fallback
  swift build --package-path "$ROOT_DIR/External/SDLKit" -c debug | tee -a "$LOG_FILE"
  SDLKIT_DEMO_FORCE_2D=1 swift run --package-path "$ROOT_DIR/External/SDLKit" SDLKitDemo | tee -a "$LOG_FILE"
fi

echo "[visuals] Done. Log: $LOG_FILE" | tee -a "$LOG_FILE"

