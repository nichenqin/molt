#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

VERSION="${1:?usage: Scripts/update-homebrew.sh <version> <dist>}"
DIST="${2:-dist}"
REPO="nichenqin/molt"
TAG="v$VERSION"
BASE="https://github.com/$REPO/releases/download/$TAG"

sha() {
  shasum -a 256 "$1" | awk '{print $1}'
}

CLI_SHA="$(sha "$DIST/molt-cli")"
DMG_SHA="$(sha "$DIST/Molt-macos.dmg")"

mkdir -p Formula Casks

cat > Formula/molt.rb <<EOF
class Molt < Formula
  desc "Every macOS update in one place: brew, npm, apps, and CLI tools"
  homepage "https://nichenqin.github.io/molt/"
  url "$BASE/molt-cli"
  version "$VERSION"
  sha256 "$CLI_SHA"
  license "MIT"

  def install
    bin.install "molt-cli" => "molt"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/molt version")
  end
end
EOF

cat > Casks/molt-app.rb <<EOF
cask "molt-app" do
  version "$VERSION"
  sha256 "$DMG_SHA"

  url "$BASE/Molt-macos.dmg"
  name "Molt"
  desc "Every update in one place"
  homepage "https://nichenqin.github.io/molt/"

  auto_updates true
  depends_on macos: :sonoma

  app "Molt.app"
end
EOF

echo "Updated Formula/molt.rb and Casks/molt-app.rb for $VERSION"
