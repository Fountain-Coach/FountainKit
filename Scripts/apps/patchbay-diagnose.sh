#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 [--kill] [--seconds N]

Samples the running PatchBay app process and writes artifacts under .fountain/artifacts/diagnostics.

Options:
  --kill         Send SIGKILL after sampling (use when the app is unresponsive)
  --seconds N    Sampling duration in seconds (default: 5)

Artifacts:
  - sample-<pid>.txt: stack sample from 'sample' utility
  - patchbay-app.log: copied from .fountain/logs (if PATCHBAY_DEBUG=1 was enabled)
  - ps.txt: process list filtered for patchbay/gateway
EOF
}

KILL=0
SEC=5
while [[ $# -gt 0 ]]; do
  case "$1" in
    --kill) KILL=1; shift ;;
    --seconds) SEC=${2:-5}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 2 ;;
  esac
done

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ART_DIR="$ROOT_DIR/.fountain/artifacts/diagnostics/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$ART_DIR"

# Try to find patchbay-app process (swift run name) or app bundle name
PID=""
if command -v pgrep >/dev/null 2>&1; then
  PID=$(pgrep -f "patchbay-app|PatchBay Studio" | head -n1 || true)
fi
if [[ -z "$PID" ]]; then
  echo "No running PatchBay app found (by name). Is it started?" >&2
  exit 1
fi
echo "Found PatchBay PID: $PID"

if command -v sample >/dev/null 2>&1; then
  echo "Sampling $PID for $SEC seconds…"
  sample "$PID" "$SEC" -file "$ART_DIR/sample-$PID.txt" || true
else
  echo "'sample' utility not available; skipping stack sample." >&2
fi

# Collect logs
if [[ -f "$ROOT_DIR/.fountain/logs/patchbay-app.log" ]]; then
  cp "$ROOT_DIR/.fountain/logs/patchbay-app.log" "$ART_DIR/"
fi
ps auxww | rg -i "patchbay|gateway|tool|service" || true > "$ART_DIR/ps.txt"

echo "Wrote diagnostics to: $ART_DIR"

if [[ "$KILL" == "1" ]]; then
  echo "Sending SIGKILL to $PID"
  kill -9 "$PID" || true
fi

