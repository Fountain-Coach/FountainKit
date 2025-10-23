#!/usr/bin/env bash
set -euo pipefail

# Launch the fresh Composer Studio app (composer-first).
# Usage:
#   Scripts/launch-composer-studio.sh [--autostart]

AUTOSTART=0
for a in "$@"; do case "$a" in --autostart) AUTOSTART=1;; esac; done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export FOUNTAINKIT_ROOT="$REPO_ROOT"

# Seed launcher signature to avoid server nags if user runs servers from here
export LAUNCHER_SIGNATURE="${LAUNCHER_SIGNATURE:-$(security find-generic-password -s FountainAI -a LAUNCHER_SIGNATURE -w 2>/dev/null || echo B86D7CEE-24C4-4C4C-A107-8D0542D1965B)}"

if [[ "$AUTOSTART" == "1" ]]; then
  export AUDIO_TALK_AUTOSTART=1
fi

swift run --package-path "$REPO_ROOT/Packages/FountainApps" composer-studio

