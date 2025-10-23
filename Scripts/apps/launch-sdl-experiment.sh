#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

if [[ ! -d "$ROOT_DIR/External/SDLKit" || -z "$(ls -A "$ROOT_DIR/External/SDLKit" 2>/dev/null || true)" ]]; then
  echo "[sdl-experiment] SDLKit submodule not present. Run:" >&2
  echo "  git submodule update --init --recursive External/SDLKit" >&2
  exit 2
fi

echo "[sdl-experiment] Building…"
swift build --package-path "$ROOT_DIR/Packages/SDLExperiment" -c debug

echo "[sdl-experiment] Running…"
swift run --package-path "$ROOT_DIR/Packages/SDLExperiment" sdl-composer-experiment

