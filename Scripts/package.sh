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
  swift build -c "$CONFIG" --product molt --arch arm64 --arch x86_64
  swift build -c "$CONFIG" --product MoltApp --arch arm64 --arch x86_64
  BUILD_DIR=".build/apple/Products/Release"
else
  swift build -c "$CONFIG" --product molt --arch "$ARCHS"
  swift build -c "$CONFIG" --product MoltApp --arch "$ARCHS"
  BUILD_DIR=".build/$ARCHS-apple-macosx/$CONFIG"
fi

rm -rf "$APP" "$DIST/molt" "$DIST/Molt-macos.zip" "$DIST/Molt-macos.zip.sha256"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$DIST"

cp "$BUILD_DIR/MoltApp" "$APP/Contents/MacOS/Molt"
cp "$BUILD_DIR/molt" "$DIST/molt"
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
