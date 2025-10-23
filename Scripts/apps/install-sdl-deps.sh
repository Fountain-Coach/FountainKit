#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname)" != "Darwin" ]]; then
  echo "This helper targets macOS with Homebrew. On Linux, install SDL3 via your package manager." >&2
  exit 2
fi
if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew not found. Install from https://brew.sh and re-run." >&2
  exit 2
fi

echo "Installing SDL3, SDL3_image, SDL3_ttf…"
brew install sdl3 sdl3_image sdl3_ttf
echo "Done. You can now run: Scripts/apps/launch-sdl-experiment.sh"

