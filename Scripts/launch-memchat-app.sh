#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="debug"
CLEAN_BUILD=0
for a in "$@"; do
  if [[ "$a" == "release" ]]; then CONFIGURATION="release"; fi
  if [[ "$a" == "--fresh" || "$a" == "--clean" ]]; then CLEAN_BUILD=1; fi
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$CLEAN_BUILD" == "1" ]]; then
  echo "› Cleaning FountainApps build artifacts (${CONFIGURATION})"
  swift package --package-path "${REPO_ROOT}/Packages/FountainApps" clean || true
fi
echo "› Building memchat-app (${CONFIGURATION})"
swift build --package-path "${REPO_ROOT}/Packages/FountainApps" --configuration "${CONFIGURATION}" --product memchat-app
BIN_PATH="$(swift build --package-path "${REPO_ROOT}/Packages/FountainApps" --configuration "${CONFIGURATION}" --show-bin-path)"
EXECUTABLE="${BIN_PATH}/memchat-app"

if [[ ! -x "${EXECUTABLE}" ]]; then
  ALT_EXECUTABLE="${BIN_PATH}/memchat-app.app/Contents/MacOS/memchat-app"
  if [[ -x "${ALT_EXECUTABLE}" ]]; then
    EXECUTABLE="${ALT_EXECUTABLE}"
  fi
fi

APP_BUNDLE="${BIN_PATH}/memchat-app.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RESOURCES_DIR="${CONTENTS}/Resources"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Resolve signature from Keychain or fallback
SIG="$(security find-generic-password -s FountainAI -a LAUNCHER_SIGNATURE -w 2>/dev/null || true)"
if [[ -z "${SIG}" ]]; then SIG="B86D7CEE-24C4-4C4C-A107-8D0542D1965B"; fi

# Resolve default store dir early so we can wire Semantic Browser to the same store/corpus
STORE_DIR="${FOUNTAINSTORE_DIR:-${REPO_ROOT}/.fountain/store}"

# Ensure a headless Chrome (CDP) is running and export SB_CDP_URL
if [[ -z "${SB_CDP_URL:-}" ]]; then
  CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  if pgrep -f "--remote-debugging-port=9222" >/dev/null 2>&1; then
    : # already running
  else
    if [[ -x "$CHROME" ]]; then
      echo "› Starting headless Chrome (CDP on :9222)"
      "$CHROME" --headless=new --disable-gpu --remote-debugging-port=9222 --user-data-dir="/tmp/memchat-chrome" >/dev/null 2>&1 &
      sleep 0.8
    fi
  fi
  # Discover WS URL
  SB_CDP_URL=$(curl -sf --max-time 2 http://127.0.0.1:9222/json/version | python3 -c 'import sys,json;print(json.load(sys.stdin).get("webSocketDebuggerUrl",""))' 2>/dev/null || true)
fi
if [[ -n "${SB_CDP_URL:-}" ]]; then
  echo "› CDP: ${SB_CDP_URL}"
else
  echo "[launch-memchat] WARNING: No SB_CDP_URL available. Semantic Browser will refuse to start unless SB_ALLOW_URLFETCH=1 is set."
fi

# Ensure core services are up (Awareness, Bootstrap, Semantic Browser, Gateway)
echo "› Ensuring local Fountain services (Awareness/Bootstrap/Browser/Gateway)…"
# Pass SB_STORE_PATH/SB_STORE_CORPUS and SB_CDP_URL so the Semantic Browser indexes into the same store+corpus
DEV_UP_USE_BIN=1 DEV_UP_CHECKS=1 DEV_UP_NO_START_LOCAL_AGENT=1 \
  SB_STORE_PATH="${STORE_DIR}" SB_STORE_CORPUS="${MEMORY_CORPUS_ID:-memchat-app}" SB_CDP_URL="${SB_CDP_URL:-}" \
  bash "${REPO_ROOT}/Scripts/dev-up" --all || true

# Resolve OpenAI API key from Keychain only; fail fast if missing
OPENAI_KEY="$(security find-generic-password -s FountainAI -a OPENAI_API_KEY -w 2>/dev/null || true)"
if [[ -z "${OPENAI_KEY}" ]]; then
  echo "[launch-memchat] ERROR: No OPENAI_API_KEY found in Keychain (service=FountainAI, account=OPENAI_API_KEY) or environment."
  echo "Set it in Keychain or export OPENAI_API_KEY and re-run."
  exit 1
fi

# Preflight: verify OpenAI connectivity using Keychain key (no secret printed)
HTTP_CODE=$(curl -sS -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer ${OPENAI_KEY}" \
  -H "Content-Type: application/json" \
  --max-time 6 \
  https://api.openai.com/v1/models || true)
if [[ "${HTTP_CODE}" != 2* && "${HTTP_CODE}" != 3* && "${HTTP_CODE}" != "200" ]]; then
  echo "[launch-memchat] ERROR: OpenAI connectivity check failed (/v1/models), HTTP ${HTTP_CODE:-n/a}."
  exit 2
fi

# STORE_DIR already resolved above

cat > "${CONTENTS}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>memchat-app</string>
  <key>CFBundleIdentifier</key><string>com.fountaincoach.memchat</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>MemChat</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>LSEnvironment</key>
  <dict>
    <key>FOUNTAINSTORE_DIR</key><string>${STORE_DIR}</string>
    <key>MEMORY_CORPUS_ID</key><string>${MEMORY_CORPUS_ID:-memchat-app}</string>
    <key>OPENAI_API_URL</key><string>${OPENAI_API_URL:-}</string>
    <key>SEMANTIC_BROWSER_URL</key><string>${SEMANTIC_BROWSER_URL:-http://127.0.0.1:8007}</string>
    <!-- Local LLM disabled by policy -->
    <key>FOUNTAIN_GATEWAY_URL</key><string>${FOUNTAIN_GATEWAY_URL:-}</string>
    <key>AWARENESS_URL</key><string>${AWARENESS_URL:-http://127.0.0.1:8001}</string>
    <key>BOOTSTRAP_URL</key><string>${BOOTSTRAP_URL:-http://127.0.0.1:8002}</string>
    <key>LAUNCHER_SIGNATURE</key><string>${SIG}</string>
  </dict>
</dict>
</plist>
PLIST

cp "${EXECUTABLE}" "${MACOS_DIR}/memchat-app" || true
chmod +x "${MACOS_DIR}/memchat-app"

if command -v codesign >/dev/null 2>&1; then
echo "› Codesigning ${APP_BUNDLE} (ad-hoc)"
  codesign --force --deep --sign - "${APP_BUNDLE}" || true
fi

# Stop any existing MemChat instance to avoid stale UI
if pgrep -f "/memchat-app.app/Contents/MacOS/memchat-app" >/dev/null 2>&1; then
  echo "› Stopping existing MemChat instances"
  pkill -f "/memchat-app.app/Contents/MacOS/memchat-app" || true
  sleep 0.4
fi

echo "› Launching ${APP_BUNDLE} (new instance)"
open -n "${APP_BUNDLE}"
