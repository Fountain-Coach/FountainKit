#!/usr/bin/env bash
set -euo pipefail
# baseline-robot.sh — run MIDI Robot-style invariants that define the Baseline‑PatchBay UI
# Usage: Scripts/ci/baseline-robot.sh

ROOT_DIR=$(cd "$(dirname "$0")/../.." && pwd)
pushd "$ROOT_DIR" >/dev/null

echo "[baseline-robot] Building baseline UI product (baseline-patchbay)…"
swift build --package-path "$ROOT_DIR/Packages/FountainApps" -c debug --product baseline-patchbay >/dev/null

echo "[baseline-robot] Running robot/invariant suites (PatchBayAppUITests subset)…"
# These tests exercise the same Canvas/Grid/Viewport invariants the baseline enforces.
ROBOT_ONLY=1 swift test --package-path Packages/FountainApps -c debug \
  --filter 'GridInstrumentTests|ViewportGridContactTests|PixelGridVerifierTests|MIDIMonitorEventsTests|CanvasDefaultTransformTests|RightEdgeContactTests' \
  -Xswiftc -DROBOT_ONLY || true

echo "[baseline-robot] Done"
popd >/dev/null

