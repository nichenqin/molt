#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

VERSION="${1:?usage: Scripts/update-homebrew.sh <version> <dist>}"
DIST="${2:-dist}"
REPO="nichenqin/remige"
BASE="https://github.com/$REPO/releases/download"

sha() {
  shasum -a 256 "$1" | awk '{print $1}'
}

CLI_SHA="$(sha "$DIST/remige-cli")"
DMG_SHA="$(sha "$DIST/Remige-macos.dmg")"

mkdir -p Formula Casks

cat > Formula/remige.rb <<EOF
class Remige < Formula
  desc "Every macOS update in one place: brew, npm, apps, and CLI tools"
  homepage "https://remige.app/"
  url "$BASE/v#{version}/remige-cli"
  version "$VERSION"
  sha256 "$CLI_SHA"
  license "MIT"

  def install
    bin.install "remige-cli" => "remige"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/remige version")
  end
end
EOF

cat > Casks/remige-app.rb <<EOF
cask "remige-app" do
  version "$VERSION"
  sha256 "$DMG_SHA"

  url "$BASE/v#{version}/Remige-macos.dmg"
  name "Remige"
  desc "Every update in one place"
  homepage "https://remige.app/"

  auto_updates true
  depends_on macos: :sonoma

  app "Remige.app"
end
EOF

echo "Updated Formula/remige.rb and Casks/remige-app.rb for $VERSION"
