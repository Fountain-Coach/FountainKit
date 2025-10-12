#!/bin/bash
set -euo pipefail

export LAUNCHER_SIGNATURE=${LAUNCHER_SIGNATURE:-B86D7CEE-24C4-4C4C-A107-8D0542D1965B}
export FOUNTAINSTORE_PORT=${FOUNTAINSTORE_PORT:-8005}

LOG_FILE=${PERSIST_LOG_FILE:-$HOME/.fountain/persist.log}
mkdir -p "$(dirname "$LOG_FILE")"
: > "$LOG_FILE"

function log {
  printf '[persist] %s\n' "$1" | tee -a "$LOG_FILE"
}

log "Launching persist-server on port ${FOUNTAINSTORE_PORT} (signature ${LAUNCHER_SIGNATURE})"
log "Streaming build/runtime logs to $LOG_FILE"
log "Stop with Ctrl+C. Override port via FOUNTAINSTORE_PORT, signature via LAUNCHER_SIGNATURE."
log "Tail logs with: tail -f $LOG_FILE"

swift run --package-path Packages/FountainApps persist-server "$@" 2>&1 | tee -a "$LOG_FILE"
