#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CFG="${1:-debug}"
export CLANG_MODULE_CACHE_PATH="$ROOT/.fountain/clang-module-cache"
export SWIFTPM_ENABLE_SANDBOX=0
swift build --package-path "$ROOT/Packages/FountainApps" -c "$CFG" --target metalviewkit-runtime-server
BIN="$(swift build --package-path "$ROOT/Packages/FountainApps" -c "$CFG" --show-bin-path)"
exec "$BIN/metalviewkit-runtime-server"

