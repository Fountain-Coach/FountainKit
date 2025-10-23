#!/usr/bin/env bash
set -euo pipefail

# Stops the AudioTalk dev stack (tools-factory, function-caller, audiotalk)
# Uses PID files under ~/.fountain and frees TCP ports if needed.

LOG_DIR="$HOME/.fountain"

log() { printf "\033[1;34m›\033[0m %s\n" "$*"; }
is_running() { local pid="$1"; kill -0 "$pid" 2>/dev/null; }

stop_by_pidfile() {
  local label="$1"; local pidfile="$2"
  if [[ -f "$pidfile" ]]; then
    local pid; pid="$(cat "$pidfile" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && is_running "$pid"; then
      log "Stopping $label (pid=$pid)"
      kill "$pid" 2>/dev/null || true; sleep 1
      if is_running "$pid"; then kill -KILL "$pid" 2>/dev/null || true; fi
    fi
    rm -f "$pidfile" || true
  fi
}

stop_by_port() {
  local port="$1"; local label="$2"
  local pids
  pids="$(lsof -ti tcp:"$port" 2>/dev/null || true)"
  if [[ -n "$pids" ]]; then
    for p in $pids; do
      log "Killing pid=$p holding :$port ($label)"
      kill "$p" 2>/dev/null || true; sleep 1
      kill -KILL "$p" 2>/dev/null || true
    done
  fi
}

stop_by_pidfile tools-factory "$LOG_DIR/tools-factory.pid"
stop_by_pidfile function-caller "$LOG_DIR/function-caller.pid"
stop_by_pidfile audiotalk "$LOG_DIR/audiotalk.pid"

# Best-effort: free ports
stop_by_port 8011 tools-factory
stop_by_port 8004 function-caller
stop_by_port 8080 audiotalk

log "AudioTalk stack stopped"
