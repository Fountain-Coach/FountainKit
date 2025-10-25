#!/usr/bin/env bash
set -euo pipefail

# metal-lib-build.sh — Build Metal .metallib artifacts outside the SwiftPM plugin sandbox.
#
# Usage:
#   Scripts/ci/metal-lib-build.sh [--package-path <path>] [--out <dir>]
#
# - Compiles native .metal sources (if present) under Shaders/{graphics,compute} of the SDLKit package.
# - Produces .air and .metallib outputs in the SDLKit Generated/metal directory by default.
# - Honors MACOSX_DEPLOYMENT_TARGET (defaults to 13.0) to reduce SDK skew issues.
# - Discovers Apple tools via xcrun -f metal/metallib if not on PATH.

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PKG_PATH="$ROOT_DIR/External/SDLKit"
OUT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --package-path)
      PKG_PATH="$2"; shift 2 ;;
    --out)
      OUT_DIR="$2"; shift 2 ;;
    *)
      echo "Usage: Scripts/ci/metal-lib-build.sh [--package-path <path>] [--out <dir>]" >&2
      exit 2 ;;
  esac
done

if [[ ! -d "$PKG_PATH" ]]; then
  echo "[metal-lib-build] Package path not found: $PKG_PATH" >&2
  exit 2
fi

if [[ -z "$OUT_DIR" ]]; then
  OUT_DIR="$PKG_PATH/Sources/SDLKit/Generated/metal"
fi

mkdir -p "$OUT_DIR"

resolve_tool() {
  local name="$1" ; shift
  local found
  if found="$(command -v "$name" 2>/dev/null)" && [[ -n "$found" ]]; then
    printf '%s' "$found"; return 0
  fi
  if command -v xcrun >/dev/null 2>&1; then
    found="$(xcrun -f "$name" 2>/dev/null || true)"
    if [[ -n "$found" && -x "$found" ]]; then
      printf '%s' "$found"; return 0
    fi
  fi
  return 1
}

METAL_BIN="$(resolve_tool metal || true)"
METALLIB_BIN="$(resolve_tool metallib || true)"

if [[ -z "$METAL_BIN" || -z "$METALLIB_BIN" ]]; then
  echo "[metal-lib-build] Apple Metal tools not found (metal/metallib). Ensure Xcode CL tools installed." >&2
  exit 3
fi

DEPLOY_MIN="${MACOSX_DEPLOYMENT_TARGET:-13.0}"
echo "[metal-lib-build] Using metal: $METAL_BIN, metallib: $METALLIB_BIN, min macOS: $DEPLOY_MIN"

build_one() {
  local src="$1"
  local base
  base="$(basename "$src")"; base="${base%.metal}"
  local air="$OUT_DIR/$base.air"
  local lib="$OUT_DIR/../metal/$base.metallib"
  mkdir -p "$(dirname "$lib")"

  # Use a writable module cache dir to avoid sandbox-unfriendly paths
  local cache_dir
  cache_dir="$OUT_DIR/.metal-module-cache"
  mkdir -p "$cache_dir"

  echo "[metal-lib-build] metal -> AIR: $src -> $air"
  "$METAL_BIN" "$src" -o "$air" -mmacosx-version-min="$DEPLOY_MIN" \
    -fno-objc-arc -c \
    -Wno-unused-variable -Wno-unused-parameter \
    -Wno-unused-function -Wno-missing-prototypes \
    -Wno-shorten-64-to-32 \
    -Wno-documentation \
    -Wno-overriding-method-mismatch \
    -Wno-unused-private-field \
    -Wno-nonportable-include-path \
    -Werror \
    1>/dev/null

  echo "[metal-lib-build] metallib: $air -> $lib"
  "$METALLIB_BIN" "$air" -o "$lib"
}

shopt -s nullglob
GRAPHICS=()
COMPUTE=()
GRAPHICS=( "$PKG_PATH/Shaders/graphics"/*.metal )
COMPUTE=( "$PKG_PATH/Shaders/compute"/*.metal )
TOTAL=0

if [[ ${GRAPHICS+set} == set ]]; then
  for src in "${GRAPHICS[@]}"; do
    build_one "$src"; TOTAL=$((TOTAL+1))
  done
fi
if [[ ${COMPUTE+set} == set ]]; then
  for src in "${COMPUTE[@]}"; do
    build_one "$src"; TOTAL=$((TOTAL+1))
  done
fi

if [[ $TOTAL -eq 0 ]]; then
  echo "[metal-lib-build] No native .metal sources found under $PKG_PATH/Shaders" >&2
  exit 4
fi

echo "[metal-lib-build] Built $TOTAL metallib artifact(s) into $(cd "$OUT_DIR/../metal" && pwd)"
