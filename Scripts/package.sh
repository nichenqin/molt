#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
ARCHS="${ARCHS:-arm64}"
VERSION="${VERSION:-0.1.0}"
DIST="dist"
APP="$DIST/Remige.app"

echo "Building Remige $VERSION ($ARCHS)"
if [ "$ARCHS" = "universal" ]; then
  # Build each slice with SwiftPM, then lipo. SwiftPM's `--arch` shortcut goes
  # through Xcode's package build and has had SWIFT_VERSION bugs on some runners.
  for arch in arm64 x86_64; do
    swift build -c "$CONFIG" --product remige --triple "$arch-apple-macosx14.0"
    swift build -c "$CONFIG" --product RemigeApp --triple "$arch-apple-macosx14.0"
  done
  BUILD_DIR=".build/arm64-apple-macosx/$CONFIG"
  mkdir -p "$DIST"
  lipo -create \
    ".build/arm64-apple-macosx/$CONFIG/remige" \
    ".build/x86_64-apple-macosx/$CONFIG/remige" \
    -output "$DIST/remige"
  lipo -create \
    ".build/arm64-apple-macosx/$CONFIG/RemigeApp" \
    ".build/x86_64-apple-macosx/$CONFIG/RemigeApp" \
    -output "$DIST/RemigeApp-universal"
  APP_BINARY="$DIST/RemigeApp-universal"
  CLI_BINARY="$DIST/remige"
else
  swift build -c "$CONFIG" --product remige --arch "$ARCHS"
  swift build -c "$CONFIG" --product RemigeApp --arch "$ARCHS"
  BUILD_DIR=".build/$ARCHS-apple-macosx/$CONFIG"
  APP_BINARY="$BUILD_DIR/RemigeApp"
  CLI_BINARY="$BUILD_DIR/remige"
fi

rm -rf "$APP" "$DIST/Remige-macos.zip" "$DIST/Remige-macos.zip.sha256"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$DIST"

cp "$APP_BINARY" "$APP/Contents/MacOS/Remige"
if [ "$CLI_BINARY" != "$DIST/remige" ]; then
  cp "$CLI_BINARY" "$DIST/remige"
fi
if [ "$ARCHS" = "universal" ]; then
  rm -f "$DIST/RemigeApp-universal"
fi
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
RES_BUNDLE="$BUILD_DIR/Remige_RemigeApp.bundle"
if [ -d "$RES_BUNDLE/Contents/Resources" ]; then
  RES_SRC="$RES_BUNDLE/Contents/Resources"
else
  RES_SRC="$RES_BUNDLE"
fi
for lproj in "$RES_SRC"/*.lproj; do
  [ -d "$lproj" ] && cp -R "$lproj" "$APP/Contents/Resources/"
done
if [ ! -d "$APP/Contents/Resources/en.lproj" ]; then
  echo "error: localization resources were not copied into the app bundle" >&2
  exit 1
fi
# Local builds are ad-hoc signed; a Developer ID identity enables hardened
# runtime signing. Notarisation is opt-in through a keychain profile or Apple
# API/Apple ID credentials.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

SIGNED=0
if [ -n "${CODESIGN_ID:-}" ]; then
  codesign --force --options runtime --timestamp --sign "$CODESIGN_ID" "$APP"
  SIGNED=1
else
  codesign --force --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"

DMG="$DIST/Remige-macos.dmg"
rm -f "$DMG"
DMG_ROOT="$DIST/.dmg-root"
rm -rf "$DMG_ROOT"
mkdir -p "$DMG_ROOT"
ditto "$APP" "$DMG_ROOT/Remige.app"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create -volname "Remige" -srcfolder "$DMG_ROOT" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$DMG_ROOT"
if [ "$SIGNED" = "1" ]; then
  codesign --force --timestamp --sign "$CODESIGN_ID" "$DMG"
fi

notarize() {
  if [ -n "${NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
    return
  fi
  if [ -n "${APPLE_API_KEY_P8:-}" ] && [ -n "${APPLE_API_KEY_ID:-}" ] && [ -n "${APPLE_API_ISSUER:-}" ]; then
    KEY="$DIST/.notary-key.p8"
    printf '%s' "$APPLE_API_KEY_P8" > "$KEY"
    xcrun notarytool submit "$1" --key "$KEY" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER" --wait
    rm -f "$KEY"
    return
  fi
  if [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ]; then
    xcrun notarytool submit "$1" --apple-id "$APPLE_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" --team-id "$APPLE_TEAM_ID" --wait
    return
  fi
  return 1
}

if [ "$SIGNED" = "1" ] && notarize "$DMG"; then
  xcrun stapler staple "$DMG"
  xcrun stapler staple "$APP"
  spctl --assess --type execute --verbose=2 "$APP"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
  echo "Notarised and stapled."
else
  if [ "$SIGNED" = "1" ]; then
    echo "warning: signed but no notarisation credentials; users may see a Gatekeeper prompt." >&2
  else
    echo "Ad-hoc signed build (set CODESIGN_ID + notarisation credentials for a public release)."
  fi
fi

ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/Remige-macos.zip"
cp "$DIST/remige" "$DIST/remige-cli"
(cd "$DIST" && shasum -a 256 Remige-macos.zip Remige-macos.dmg remige-cli > Remige-macos.zip.sha256)

echo "App:  $APP"
echo "CLI:  $DIST/remige"
echo "DMG:  $DMG"
echo "Zip:  $DIST/Remige-macos.zip"
ls -lh "$DIST/Remige-macos.zip" "$DIST/Remige-macos.dmg" "$DIST/remige"
