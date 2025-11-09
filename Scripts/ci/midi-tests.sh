#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

echo "[ci] Running MIDI telemetry tests (safe iteration + inbound off)…"
swift test --package-path "$ROOT/Packages/FountainTelemetryKit" -c debug --filter MIDI2TransportsTests

echo "[ci] Done."

