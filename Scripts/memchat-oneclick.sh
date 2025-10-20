#!/usr/bin/env bash
set -euo pipefail

# One-click starter for MemChat.
# - Boots local services (Awareness/Bootstrap/Semantic Browser/Gateway)
# - Ensures CDP is running and wires SB_CDP_URL
# - Launches either the memchat-app (default) or memchat-teatro
#
# Usage:
#   Scripts/memchat-oneclick.sh [--fresh] [release] [--teatro|--app]

MODE="app"            # app | teatro
CONFIGURATION="debug"  # debug | release
CLEAN_BUILD=0
for a in "$@"; do
  case "$a" in
    --teatro) MODE="teatro" ;;
    --app) MODE="app" ;;
    --fresh|--clean) CLEAN_BUILD=1 ;;
    release) CONFIGURATION="release" ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STORE_DIR="${FOUNTAINSTORE_DIR:-${REPO_ROOT}/.fountain/store}"
CORPUS_ID="${MEMORY_CORPUS_ID:-memchat-app}"

# Ensure OpenAI API key exists (required for MemChat providers)
OPENAI_KEY="$(security find-generic-password -s FountainAI -a OPENAI_API_KEY -w 2>/dev/null || true)"
if [[ -z "${OPENAI_KEY}" ]]; then
  echo "[memchat-oneclick] ERROR: No OPENAI_API_KEY in Keychain (service=FountainAI, account=OPENAI_API_KEY)."
  exit 1
fi

# Start headless Chrome and derive SB_CDP_URL if not provided
if [[ -z "${SB_CDP_URL:-}" ]]; then
  CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  if ! pgrep -f "--remote-debugging-port=9222" >/dev/null 2>&1; then
    if [[ -x "$CHROME" ]]; then
      echo "› Starting headless Chrome (CDP on :9222)"
      "$CHROME" --headless=new --disable-gpu --remote-debugging-port=9222 --user-data-dir="/tmp/memchat-chrome" >/dev/null 2>&1 &
      sleep 0.8
    fi
  fi
  SB_CDP_URL=$(curl -sf --max-time 2 http://127.0.0.1:9222/json/version | python3 -c 'import sys,json;print(json.load(sys.stdin).get("webSocketDebuggerUrl",""))' 2>/dev/null || true)
fi
if [[ -n "${SB_CDP_URL:-}" ]]; then
  echo "› CDP: ${SB_CDP_URL}"
else
  echo "[memchat-oneclick] WARNING: No SB_CDP_URL available; set SB_ALLOW_URLFETCH=1 to allow non-JS fetchers."
fi

# Start dev services (Awareness/Bootstrap/Semantic Browser/Gateway) and wire store/corpus
echo "› Ensuring local services…"
DEV_UP_USE_BIN=1 DEV_UP_CHECKS=1 DEV_UP_NO_START_LOCAL_AGENT=1 \
  SB_STORE_PATH="${STORE_DIR}" SB_STORE_CORPUS="${CORPUS_ID}" SB_CDP_URL="${SB_CDP_URL:-}" \
  bash "${REPO_ROOT}/Scripts/dev-up" --all || true

if [[ "${MODE}" == "app" ]]; then
  echo "› Launching memchat-app (configuration=${CONFIGURATION}; fresh=${CLEAN_BUILD})"
  if [[ "${CLEAN_BUILD}" == "1" ]]; then
    swift package --package-path "${REPO_ROOT}/Packages/FountainApps" clean || true
  fi
  bash "${REPO_ROOT}/Scripts/launch-memchat-app.sh" ${CONFIGURATION} $( [[ "${CLEAN_BUILD}" == "1" ]] && echo "--fresh" )
else
  echo "› Launching memchat-teatro (configuration=${CONFIGURATION}; fresh=${CLEAN_BUILD})"
  if [[ "${CLEAN_BUILD}" == "1" ]]; then
    swift package --package-path "${REPO_ROOT}/Packages/FountainApps" clean || true
  fi
  # Run Teatro variant in the current terminal
  LAUNCHER_SIGNATURE="$(security find-generic-password -s FountainAI -a LAUNCHER_SIGNATURE -w 2>/dev/null || true)" \
  FOUNTAINSTORE_DIR="${STORE_DIR}" MEMORY_CORPUS_ID="${CORPUS_ID}" \
  SEMANTIC_BROWSER_URL="${SEMANTIC_BROWSER_URL:-http://127.0.0.1:8007}" \
  swift run --package-path "${REPO_ROOT}/Packages/FountainApps" --configuration "${CONFIGURATION}" memchat-teatro
fi

