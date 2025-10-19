#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="debug"
if [[ "${1:-}" == "release" ]]; then CONFIGURATION="release"; fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
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

# Default store dir
STORE_DIR="${FOUNTAINSTORE_DIR:-${REPO_ROOT}/.fountain/store}"

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
    <!-- Local LLM disabled by policy -->
    <key>FOUNTAIN_GATEWAY_URL</key><string>${FOUNTAIN_GATEWAY_URL:-}</string>
    <key>AWARENESS_URL</key><string>${AWARENESS_URL:-}</string>
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

echo "› Launching ${APP_BUNDLE}"
open "${APP_BUNDLE}"
