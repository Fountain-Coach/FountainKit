#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="release"
if [[ "${1:-}" == "debug" ]]; then CONFIGURATION="debug"; fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="${REPO_ROOT}/Dist"
APP_NAME="MemChat.app"

echo "› Building memchat-app (${CONFIGURATION})"
swift build --package-path "${REPO_ROOT}/Packages/FountainApps" --configuration "${CONFIGURATION}" --product memchat-app
BIN_PATH="$(swift build --package-path "${REPO_ROOT}/Packages/FountainApps" --configuration "${CONFIGURATION}" --show-bin-path)"

# Source executable (non-app) or app bundle path
SRC_EXE="${BIN_PATH}/memchat-app"
SRC_APP="${BIN_PATH}/memchat-app.app"

BUILD_APP_DIR="${BIN_PATH}/memchat-app.app"
if [[ ! -d "${BUILD_APP_DIR}" ]]; then
  mkdir -p "${BUILD_APP_DIR}/Contents/MacOS" "${BUILD_APP_DIR}/Contents/Resources"
  cp "${SRC_EXE}" "${BUILD_APP_DIR}/Contents/MacOS/memchat-app" || true
  chmod +x "${BUILD_APP_DIR}/Contents/MacOS/memchat-app"
fi

mkdir -p "${DIST_DIR}" && rm -rf "${DIST_DIR}/${APP_NAME}"
cp -R "${BUILD_APP_DIR}" "${DIST_DIR}/${APP_NAME}"

CONTENTS="${DIST_DIR}/${APP_NAME}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RESOURCES_DIR="${CONTENTS}/Resources"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# Resolve signature from Keychain or fallback
SIG="$(security find-generic-password -s FountainAI -a LAUNCHER_SIGNATURE -w 2>/dev/null || true)"
if [[ -z "${SIG}" ]]; then SIG="B86D7CEE-24C4-4C4C-A107-8D0542D1965B"; fi

# Resolve OpenAI API key from Keychain only; fail if missing
OPENAI_KEY="$(security find-generic-password -s FountainAI -a OPENAI_API_KEY -w 2>/dev/null || true)"
if [[ -z "${OPENAI_KEY}" ]]; then
  echo "[package-memchat] ERROR: No OPENAI_API_KEY found in Keychain (service=FountainAI, account=OPENAI_API_KEY)."
  exit 1
fi

# Defaults; override by exporting env before running
STORE_DIR="${FOUNTAINSTORE_DIR:-${REPO_ROOT}/.fountain/store}"
MEMORY_ID="${MEMORY_CORPUS_ID:-memchat-app}"

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
    <key>MEMORY_CORPUS_ID</key><string>${MEMORY_ID}</string>
    <key>OPENAI_API_URL</key><string>${OPENAI_API_URL:-}</string>
    <!-- Local LLM disabled by policy -->
    <key>FOUNTAIN_GATEWAY_URL</key><string>${FOUNTAIN_GATEWAY_URL:-}</string>
    <key>AWARENESS_URL</key><string>${AWARENESS_URL:-}</string>
    <key>LAUNCHER_SIGNATURE</key><string>${SIG}</string>
  </dict>
</dict>
</plist>
PLIST

if command -v codesign >/dev/null 2>&1; then
  echo "› Codesigning ${DIST_DIR}/${APP_NAME} (ad-hoc)"
  codesign --force --deep --sign - "${DIST_DIR}/${APP_NAME}" || true
fi

echo "Packaged: ${DIST_DIR}/${APP_NAME}"
echo "You can now drag it into /Applications and double‑click to run."
