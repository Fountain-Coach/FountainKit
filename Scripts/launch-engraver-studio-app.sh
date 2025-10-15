#!/usr/bin/env bash

set -euo pipefail

CONFIGURATION="debug"
if [[ "${1:-}" == "release" ]]; then
    CONFIGURATION="release"
fi

echo "› Building engraver-studio-app (${CONFIGURATION})"
swift build --configuration "${CONFIGURATION}" --product engraver-studio-app
BIN_PATH="$(swift build --configuration "${CONFIGURATION}" --show-bin-path)"
EXECUTABLE="${BIN_PATH}/engraver-studio-app"

if [[ ! -x "${EXECUTABLE}" ]]; then
    ALT_EXECUTABLE="${BIN_PATH}/engraver-studio-app.app/Contents/MacOS/engraver-studio-app"
    if [[ -x "${ALT_EXECUTABLE}" ]]; then
        EXECUTABLE="${ALT_EXECUTABLE}"
    else
        echo "error: expected executable at ${EXECUTABLE} (did the build succeed?)" >&2
        exit 1
    fi
fi

APP_BUNDLE="${BIN_PATH}/engraver-studio-app.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RESOURCES_DIR="${CONTENTS}/Resources"

mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cat > "${CONTENTS}/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>EngraverStudio</string>
    <key>CFBundleIdentifier</key>
    <string>com.fountaincoach.engraver-studio</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Engraver Studio</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

cp "${EXECUTABLE}" "${MACOS_DIR}/EngraverStudio"
chmod +x "${MACOS_DIR}/EngraverStudio"

echo "› Launching ${APP_BUNDLE}"
open "${APP_BUNDLE}"
