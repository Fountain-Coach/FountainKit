#!/usr/bin/env bash
set -euo pipefail

# One-click starter for AudioTalk.
# - Boots audiotalk-server with launcher signature
# - Waits for health
# - Runs CI smoke (health/dictionary/ETag)
# - Optionally opens the web console in a browser
#
# Usage:
#   Scripts/audiotalk/oneclick.sh [--release] [--fresh] [--no-open]

CONFIGURATION="debug"  # debug | release
CLEAN_BUILD=0
OPEN_BROWSER=1
for a in "$@"; do
  case "$a" in
    --fresh|--clean) CLEAN_BUILD=1 ;;
    --release) CONFIGURATION="release" ;;
    --no-open) OPEN_BROWSER=0 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export LAUNCHER_SIGNATURE=${LAUNCHER_SIGNATURE:-B86D7CEE-24C4-4C4C-A107-8D0542D1965B}
export AUDIOTALK_PORT=${AUDIOTALK_PORT:-${PORT:-8080}}

LOG_DIR="$HOME/.fountain"
mkdir -p "$LOG_DIR"
SERVER_LOG="$LOG_DIR/audiotalk.log"
SERVER_PID="$LOG_DIR/audiotalk.pid"

echo "› Building audiotalk-server (configuration=${CONFIGURATION}; fresh=${CLEAN_BUILD})"
if [[ "$CLEAN_BUILD" == "1" ]]; then
  swift package --package-path "$REPO_ROOT/Packages/FountainApps" clean || true
fi
swift build --configuration "$CONFIGURATION" --product audiotalk-server --package-path "$REPO_ROOT/Packages/FountainApps"

echo "› Starting audiotalk-server on :$AUDIOTALK_PORT (logs: $SERVER_LOG)"
nohup env LAUNCHER_SIGNATURE="$LAUNCHER_SIGNATURE" AUDIOTALK_PORT="$AUDIOTALK_PORT" \
  swift run --configuration "$CONFIGURATION" --package-path "$REPO_ROOT/Packages/FountainApps" audiotalk-server \
  >"$SERVER_LOG" 2>&1 &
echo $! > "$SERVER_PID"

echo "› Waiting for health…"
for i in {1..30}; do
  if curl -fsS "http://127.0.0.1:$AUDIOTALK_PORT/audiotalk/meta/health" >/dev/null; then
    echo "ready"; break
  fi
  sleep 1
done

if [[ "$OPEN_BROWSER" == "1" ]]; then
  if command -v open >/dev/null 2>&1; then
    open "http://127.0.0.1:$AUDIOTALK_PORT/"
  fi
fi

echo "› Running CI smoke against http://127.0.0.1:$AUDIOTALK_PORT"
env AUDIOTALK_BASE_URL="http://127.0.0.1:$AUDIOTALK_PORT" \
  swift run --package-path "$REPO_ROOT/Packages/FountainApps" audiotalk-ci-smoke || {
    echo "[audiotalk-oneclick] Smoke failed; see $SERVER_LOG"; exit 1; }

echo "› AudioTalk ready. Logs: $SERVER_LOG"
echo "› Stop server with: kill \$(cat $SERVER_PID)"
