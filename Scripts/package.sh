#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
ARCHS="${ARCHS:-arm64}"
VERSION="${VERSION:-0.1.0}"
DIST="dist"
APP="$DIST/Molt.app"

echo "Building Molt $VERSION ($ARCHS)"
if [ "$ARCHS" = "universal" ]; then
  # Build each slice with SwiftPM, then lipo. SwiftPM's `--arch` shortcut goes
  # through Xcode's package build and has had SWIFT_VERSION bugs on some runners.
  for arch in arm64 x86_64; do
    swift build -c "$CONFIG" --product molt --triple "$arch-apple-macosx14.0"
    swift build -c "$CONFIG" --product MoltApp --triple "$arch-apple-macosx14.0"
  done
  BUILD_DIR=".build/arm64-apple-macosx/$CONFIG"
  mkdir -p "$DIST"
  lipo -create \
    ".build/arm64-apple-macosx/$CONFIG/molt" \
    ".build/x86_64-apple-macosx/$CONFIG/molt" \
    -output "$DIST/molt"
  lipo -create \
    ".build/arm64-apple-macosx/$CONFIG/MoltApp" \
    ".build/x86_64-apple-macosx/$CONFIG/MoltApp" \
    -output "$DIST/MoltApp-universal"
  APP_BINARY="$DIST/MoltApp-universal"
  CLI_BINARY="$DIST/molt"
else
  swift build -c "$CONFIG" --product molt --arch "$ARCHS"
  swift build -c "$CONFIG" --product MoltApp --arch "$ARCHS"
  BUILD_DIR=".build/$ARCHS-apple-macosx/$CONFIG"
  APP_BINARY="$BUILD_DIR/MoltApp"
  CLI_BINARY="$BUILD_DIR/molt"
fi

rm -rf "$APP" "$DIST/Molt-macos.zip" "$DIST/Molt-macos.zip.sha256"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$DIST"

cp "$APP_BINARY" "$APP/Contents/MacOS/Molt"
if [ "$CLI_BINARY" != "$DIST/molt" ]; then
  cp "$CLI_BINARY" "$DIST/molt"
fi
if [ "$ARCHS" = "universal" ]; then
  rm -f "$DIST/MoltApp-universal"
fi
cp Resources/Info.plist "$APP/Contents/Info.plist"
 cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R "$BUILD_DIR/Molt_MoltApp.bundle" "$APP/Contents/Resources/"
# Local builds are ad-hoc signed. Set CODESIGN_ID for a Developer ID release.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

if [ -n "${CODESIGN_ID:-}" ]; then
  codesign --force --deep --options runtime --sign "$CODESIGN_ID" "$APP"
else
  codesign --force --deep --sign - "$APP"
fi

codesign --verify --deep --strict "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/Molt-macos.zip"
cp "$DIST/molt" "$DIST/molt-cli"
(cd "$DIST" && shasum -a 256 Molt-macos.zip molt-cli > Molt-macos.zip.sha256)

echo "App:  $APP"
echo "CLI:  $DIST/molt"
echo "Zip:  $DIST/Molt-macos.zip"
ls -lh "$DIST/Molt-macos.zip" "$DIST/molt"
