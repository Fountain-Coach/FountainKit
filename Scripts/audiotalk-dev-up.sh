#!/usr/bin/env bash
set -euo pipefail

# AudioTalk dev stack one-click starter
# Spins up:
#  - audiotalk-server (:8080)
#  - tools-factory-server (:8011)
#  - function-caller-server (:8004) with FUNCTION_CALLER_BASE_URL
# And registers AudioTalk tools into the Tools Factory.
#
# Usage:
#   Scripts/audiotalk-dev-up.sh [--release] [--fresh] [--no-register]

CONFIGURATION=debug   # debug | release
CLEAN_BUILD=0
DO_REGISTER=1
for a in "$@"; do
  case "$a" in
    --release) CONFIGURATION=release ;;
    --fresh|--clean) CLEAN_BUILD=1 ;;
    --no-register) DO_REGISTER=0 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export FOUNTAIN_SKIP_LAUNCHER_SIG=1
export AUDIOTALK_PORT=${AUDIOTALK_PORT:-8080}
export TOOLS_FACTORY_PORT=${TOOLS_FACTORY_PORT:-8011}
export FUNCTION_CALLER_PORT=${FUNCTION_CALLER_PORT:-8004}
export FUNCTION_CALLER_BASE_URL=${FUNCTION_CALLER_BASE_URL:-http://127.0.0.1:${AUDIOTALK_PORT}/audiotalk/v1}

LOG_DIR="$HOME/.fountain"
mkdir -p "$LOG_DIR"

log() { printf "\033[1;34m›\033[0m %s\n" "$*"; }
wait_for() {
  local url="$1"; local tries="${2:-30}"; local name="${3:-service}"
  for i in $(seq 1 "$tries"); do
    if curl -fsS "$url" >/dev/null; then log "$name ready"; return 0; fi
    sleep 1
  done
  echo "[ERR] $name did not become ready at $url" >&2; return 1
}

if [[ "$CLEAN_BUILD" == "1" ]]; then
  log "Cleaning build artifacts (configuration=$CONFIGURATION)"
  swift package --package-path "$REPO_ROOT/Packages/FountainApps" clean || true
fi

log "Building servers (configuration=$CONFIGURATION)"
swift build --configuration "$CONFIGURATION" --package-path "$REPO_ROOT/Packages/FountainApps" \
  --product audiotalk-server --product tools-factory-server --product function-caller-server

log "Starting tools-factory-server on :$TOOLS_FACTORY_PORT"
nohup env TOOLS_FACTORY_PORT="$TOOLS_FACTORY_PORT" \
  swift run --configuration "$CONFIGURATION" --package-path "$REPO_ROOT/Packages/FountainApps" tools-factory-server \
  >"$LOG_DIR/tools-factory.log" 2>&1 & echo $! > "$LOG_DIR/tools-factory.pid"

log "Starting function-caller-server on :$FUNCTION_CALLER_PORT (base=$FUNCTION_CALLER_BASE_URL)"
nohup env FUNCTION_CALLER_PORT="$FUNCTION_CALLER_PORT" FUNCTION_CALLER_BASE_URL="$FUNCTION_CALLER_BASE_URL" \
  swift run --configuration "$CONFIGURATION" --package-path "$REPO_ROOT/Packages/FountainApps" function-caller-server \
  >"$LOG_DIR/function-caller.log" 2>&1 & echo $! > "$LOG_DIR/function-caller.pid"

log "Starting audiotalk-server on :$AUDIOTALK_PORT"
nohup env AUDIOTALK_PORT="$AUDIOTALK_PORT" FOUNTAIN_SKIP_LAUNCHER_SIG=1 \
  swift run --configuration "$CONFIGURATION" --package-path "$REPO_ROOT/Packages/FountainApps" audiotalk-server \
  >"$LOG_DIR/audiotalk.log" 2>&1 & echo $! > "$LOG_DIR/audiotalk.pid"

log "Waiting for services to become ready"
wait_for "http://127.0.0.1:$TOOLS_FACTORY_PORT/metrics" 30 "tools-factory"
wait_for "http://127.0.0.1:$FUNCTION_CALLER_PORT/metrics" 30 "function-caller"
wait_for "http://127.0.0.1:$AUDIOTALK_PORT/audiotalk/meta/health" 30 "audiotalk"

if [[ "$DO_REGISTER" == "1" ]]; then
  log "Registering AudioTalk tools into Tools Factory (corpus=audiotalk)"
  TOOLS_FACTORY_URL="http://127.0.0.1:$TOOLS_FACTORY_PORT" TOOLS_CORPUS_ID="audiotalk" \
    bash "$REPO_ROOT/Scripts/register-audiotalk-tools.sh" || {
      echo "[WARN] Tool registration script failed. Ensure yq/jq installed or register manually." >&2; }
fi

log "Stack up. Endpoints:"
echo "  • AudioTalk     http://127.0.0.1:$AUDIOTALK_PORT/audiotalk/meta/health"
echo "  • ToolsFactory  http://127.0.0.1:$TOOLS_FACTORY_PORT/tools"
echo "  • FunctionCall  http://127.0.0.1:$FUNCTION_CALLER_PORT/functions"
echo "Logs: $LOG_DIR/{audiotalk,function-caller,tools-factory}.log"
echo "Stop with: kill \$(cat $LOG_DIR/audiotalk.pid) \$(cat $LOG_DIR/function-caller.pid) \$(cat $LOG_DIR/tools-factory.pid)"

