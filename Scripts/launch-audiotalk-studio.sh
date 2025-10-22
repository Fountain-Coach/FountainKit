#!/usr/bin/env bash
set -euo pipefail

# Launches the FountainLauncherUI app focused on the AudioTalk Studio tab,
# and (optionally) auto-starts the AudioTalk dev stack under the hood.
#
# Usage:
#   Scripts/launch-audiotalk-studio.sh [--autostart]

AUTOSTART=0
for a in "$@"; do
  case "$a" in
    --autostart) AUTOSTART=1 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export FOUNTAINKIT_ROOT="$REPO_ROOT"
export AUDIO_TALK_STUDIO=1
if [[ "$AUTOSTART" == "1" ]]; then
  export AUDIO_TALK_AUTOSTART=1
  export FOUNTAINSTORE_DIR="${FOUNTAINKIT_ROOT}/.fountain/store"
  export FUNCTION_CALLER_BASE_URL="http://127.0.0.1:8080/audiotalk/v1"
fi

swift run --package-path "$REPO_ROOT/Packages/FountainApps" FountainLauncherUI

