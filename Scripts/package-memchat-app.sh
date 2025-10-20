#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)
PKG_PATH="$REPO_ROOT/Packages/FountainApps"
CONF="${CONFIGURATION:-release}"
PRODUCT="memchat-app"
APP_NAME="MemChat"
BUNDLE_ID="coach.fountain.memchat"
OUT_DIR="$REPO_ROOT/Dist/$APP_NAME.app"

echo "[package] Building $PRODUCT ($CONF)…"
swift build --package-path "$PKG_PATH" --configuration "$CONF" --product "$PRODUCT"

BIN_DIR1="$PKG_PATH/.build/$CONF"
BIN_DIR2="$PKG_PATH/.build/arm64-apple-macosx/$CONF"
BIN=""
[[ -x "$BIN_DIR2/$PRODUCT" ]] && BIN="$BIN_DIR2/$PRODUCT"
[[ -z "$BIN" && -x "$BIN_DIR1/$PRODUCT" ]] && BIN="$BIN_DIR1/$PRODUCT"
if [[ -z "$BIN" ]]; then echo "[package] ERROR: binary not found"; exit 1; fi

echo "[package] Creating app bundle at $OUT_DIR"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/Contents/MacOS" "$OUT_DIR/Contents/Resources"

cat > "$OUT_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleExecutable</key><string>$PRODUCT</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSUIElement</key><false/>
</dict>
</plist>
PLIST

cp "$BIN" "$OUT_DIR/Contents/MacOS/$PRODUCT"
chmod +x "$OUT_DIR/Contents/MacOS/$PRODUCT"
echo "[package] Bundle created: $OUT_DIR"

