#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $(basename "$0") [--package-path Packages/FountainApps]" >&2
}

PKG_PATH=${1:-Packages/FountainApps}

echo "[pbvrt-tests] Running ROBOT_ONLY PBVRTServerTests under $PKG_PATH" >&2
ROBOT_ONLY=1 swift test --package-path "$PKG_PATH" -c debug --filter PBVRTServerTests

