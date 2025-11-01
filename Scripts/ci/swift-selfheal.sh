#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: Scripts/ci/swift-selfheal.sh [--package-path <path>] [--target <filter>] [--product <name>] [--robot-only]

Runs swift build/test with a local writable module cache to avoid sandboxed user-cache errors.

Examples:
  Scripts/ci/swift-selfheal.sh --product baseline-patchbay
  Scripts/ci/swift-selfheal.sh --target PatchBayAppUITests --robot-only
USAGE
}

PKG="Packages/FountainApps"
FILTER=""
PRODUCT=""
ROBOT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --package-path) PKG=${2:?}; shift 2 ;;
    --target) FILTER=${2:?}; shift 2 ;;
    --product) PRODUCT=${2:?}; shift 2 ;;
    --robot-only) ROBOT=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1"; usage; exit 1 ;;
  esac
done

mkdir -p .fountain/clang-module-cache .fountain/logs
export CLANG_MODULE_CACHE_PATH=$(pwd)/.fountain/clang-module-cache

if (( ROBOT )); then
  export ROBOT_ONLY=1
  export FK_ROBOT_ONLY=1
fi

echo "[selfheal] Using module cache at $CLANG_MODULE_CACHE_PATH"

if [[ -n "$PRODUCT" ]]; then
  echo "[selfheal] swift build --product $PRODUCT"
  swift build --package-path "$PKG" -c debug --product "$PRODUCT"
fi

if [[ -n "$FILTER" ]]; then
  echo "[selfheal] swift test --filter $FILTER"
  swift test --package-path "$PKG" -c debug --filter "$FILTER"
else
  echo "[selfheal] swift test (all)"
  swift test --package-path "$PKG" -c debug
fi

