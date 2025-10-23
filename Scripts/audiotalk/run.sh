#!/bin/bash
set -euo pipefail

# Provide the expected launcher signature unless supplied by the caller.
export LAUNCHER_SIGNATURE=${LAUNCHER_SIGNATURE:-B86D7CEE-24C4-4C4C-A107-8D0542D1965B}

# Configure port (defaults to 8080, or respect PORT).
export AUDIOTALK_PORT=${AUDIOTALK_PORT:-${PORT:-8080}}

LOG_FILE=${AUDIOTALK_LOG_FILE:-$HOME/.fountain/audiotalk.log}
mkdir -p "$(dirname "$LOG_FILE")"
: > "$LOG_FILE"

function log {
  printf '[audiotalk] %s\n' "$1" | tee -a "$LOG_FILE"
}

log "Launching audiotalk-server on port ${AUDIOTALK_PORT} (signature ${LAUNCHER_SIGNATURE})"
log "Streaming build/runtime logs to $LOG_FILE"
log "Stop with Ctrl+C. Override port via AUDIOTALK_PORT (or PORT), signature via LAUNCHER_SIGNATURE."
log "Tail logs with: tail -f $LOG_FILE"

swift run --package-path Packages/FountainApps audiotalk-server "$@" 2>&1 | tee -a "$LOG_FILE"
