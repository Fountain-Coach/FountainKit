#!/usr/bin/env bash
set -euo pipefail

# Launches the FountainLauncherUI app focused on the AudioTalk Studio tab,
# and (optionally) auto-starts the AudioTalk dev stack under the hood.
#
# Usage:
#   Scripts/launch-audiotalk-studio.sh [--autostart] [--use-keychain]

AUTOSTART=0
USE_KEYCHAIN=0
for a in "$@"; do
  case "$a" in
    --autostart) AUTOSTART=1 ;;
    --use-keychain) USE_KEYCHAIN=1 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export FOUNTAINKIT_ROOT="$REPO_ROOT"
export AUDIO_TALK_STUDIO=1
# Load user-provided secrets if present to avoid interactive Keychain prompts
if [[ -f "$HOME/.fountain/secrets.env" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "$HOME/.fountain/secrets.env"
  set +a
fi
if [[ "$USE_KEYCHAIN" != "1" ]]; then
  export FK_NO_KEYCHAIN=1
fi
if [[ "$AUTOSTART" == "1" ]]; then
  export AUDIO_TALK_AUTOSTART=1
  export FOUNTAINSTORE_DIR="${FOUNTAINKIT_ROOT}/.fountain/store"
  export FUNCTION_CALLER_BASE_URL="http://127.0.0.1:8080/audiotalk/v1"
fi

swift run --package-path "$REPO_ROOT/Packages/FountainApps" FountainLauncherUI
