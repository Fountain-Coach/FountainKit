#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
LOGS_DIR="$ROOT_DIR/.fountain/logs"; mkdir -p "$LOGS_DIR"

# Start Sonify app
echo "[smoke] launching quietframe-sonify-app"
(
  FOUNTAIN_SKIP_LAUNCHER_SIG=1 swift run --package-path "$ROOT_DIR/Packages/FountainApps" quietframe-sonify-app
) > "$LOGS_DIR/qf-sonify.log" 2>&1 &
APP_PID=$!
cleanup() { kill "$APP_PID" 2>/dev/null || true; }
trap cleanup EXIT

# Run smoke sender
echo "[smoke] running quietframe-smoke"
QF_NAME_CONTAINS="Quiet Frame" QF_TIMEOUT=20 swift run --package-path "$ROOT_DIR/Packages/FountainApps" quietframe-smoke
echo "[smoke] OK"

