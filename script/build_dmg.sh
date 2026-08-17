#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CursorRestorer"
DISPLAY_NAME="Cursor Restorer"
BUNDLE_ID="com.cursorrestorer.CursorRestorer"
MARKETING_VERSION="1.0"
BUILD_VERSION="1"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
BUILD_DIR="$ROOT_DIR/.build"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_SOURCE="$ROOT_DIR/Assets/CursorRestorer.png"
BACKGROUND_SOURCE="$ROOT_DIR/Assets/DMGBackground.png"
ICONSET_DIR="$BUILD_DIR/CursorRestorer.iconset"
ICON_FILE="$APP_RESOURCES/CursorRestorer.icns"
DMG_STAGE="$BUILD_DIR/CursorRestorer-dmg"
DMG_MOUNT="$BUILD_DIR/CursorRestorer-mount"
RW_DMG="$BUILD_DIR/CursorRestorer-rw.dmg"
DMG_PATH="$DIST_DIR/CursorRestorer-$MARKETING_VERSION.dmg"
VOLUME_NAME="$DISPLAY_NAME $MARKETING_VERSION"

SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
pkill -x "CursorPosRestorer" >/dev/null 2>&1 || true
pkill -x "CursorAnchor" >/dev/null 2>&1 || true

if [[ ! -f "$ICON_SOURCE" || ! -f "$BACKGROUND_SOURCE" ]]; then
  echo "Missing icon or DMG background source." >&2
  echo "Icon: $ICON_SOURCE" >&2
  echo "Background: $BACKGROUND_SOURCE" >&2
  exit 1
fi

swift build --configuration release
BUILD_BINARY="$(swift build --configuration release --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE" "$DMG_STAGE" "$DMG_MOUNT" "$ICONSET_DIR" "$RW_DMG" "$DMG_PATH"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$DMG_STAGE" "$DMG_MOUNT" "$ICONSET_DIR"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$ICON_SOURCE" "$APP_RESOURCES/CursorRestorer.png"

for size in 16 32 128 256 512; do
  double_size=$((size * 2))
  sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
  sips -z "$double_size" "$double_size" "$ICON_SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>CursorRestorer.icns</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$MARKETING_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F '"' '/Developer ID Application:/ { print $2; exit }')"
fi

if [[ -n "$SIGNING_IDENTITY" ]]; then
  codesign --force --deep --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
  SIGNING_STATUS="Developer ID signed: $SIGNING_IDENTITY"
else
  codesign --force --deep --sign - "$APP_BUNDLE"
  SIGNING_STATUS="ad hoc signed (Gatekeeper bypass/notarization still required)"
fi
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

mkdir -p "$DMG_STAGE/.background"
cp "$BACKGROUND_SOURCE" "$DMG_STAGE/.background/background.png"
cp -R "$APP_BUNDLE" "$DMG_STAGE/$DISPLAY_NAME.app"
ln -s /Applications "$DMG_STAGE/Applications"

mkdir -p "$DIST_DIR"
hdiutil create \
  -size 200m \
  -fs HFS+ \
  -volname "$VOLUME_NAME" \
  -srcfolder "$DMG_STAGE" \
  -ov \
  -format UDRW \
  "$RW_DMG" >/dev/null

hdiutil attach "$RW_DMG" -nobrowse -readwrite -mountpoint "$DMG_MOUNT" >/dev/null

if ! osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOLUME_NAME"
    open
    delay 1
    set containerWindow to container window
    set current view of containerWindow to icon view
    set toolbar visible of containerWindow to false
    set statusbar visible of containerWindow to false
    set bounds of containerWindow to {100, 100, 1000, 680}
    set viewOptions to icon view options of containerWindow
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set text size of viewOptions to 13
    set background picture of viewOptions to file ".background:background.png"
    set position of item "$DISPLAY_NAME.app" of containerWindow to {220, 310}
    set position of item "Applications" of containerWindow to {680, 310}
    close containerWindow
    open
    update without registering applications
    delay 2
    close containerWindow
  end tell
end tell
APPLESCRIPT
then
  echo "Warning: Finder could not save the DMG layout; the installer will still work." >&2
fi

hdiutil detach "$DMG_MOUNT" -quiet >/dev/null
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null
rm -rf "$DMG_MOUNT" "$RW_DMG"
hdiutil verify "$DMG_PATH" >/dev/null

if [[ -n "$NOTARY_PROFILE" ]]; then
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
else
  echo "No NOTARY_PROFILE supplied; DMG was not notarized."
fi

echo "Created: $DMG_PATH"
echo "Version: $MARKETING_VERSION ($BUILD_VERSION)"
echo "Signing: $SIGNING_STATUS"
