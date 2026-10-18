#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

mkdir -p Resources/build
swift Scripts/make-icon.swift Resources/build/icon-1024.png

ICONSET=Resources/build/AppIcon.iconset
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

for spec in \
  "16 icon_16x16.png" \
  "32 icon_16x16@2x.png" \
  "32 icon_32x32.png" \
  "64 icon_32x32@2x.png" \
  "128 icon_128x128.png" \
  "256 icon_128x128@2x.png" \
  "256 icon_256x256.png" \
  "512 icon_256x256@2x.png" \
  "512 icon_512x512.png" \
  "1024 icon_512x512@2x.png"; do
  set -- $spec
  sips -z "$1" "$1" Resources/build/icon-1024.png --out "$ICONSET/$2" >/dev/null
done

iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "Resources/AppIcon.icns"
