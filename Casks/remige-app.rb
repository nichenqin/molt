cask "remige-app" do
  version "0.3.1"
  sha256 "b7e7a7c58a119154a602604985ad41cf0d1c1b8fbbbe5c1b104875e4a71f8fa8"

  url "https://github.com/nichenqin/remige/releases/download/v0.3.1/Remige-macos.dmg"
  name "Remige"
  desc "Every update in one place"
  homepage "https://remige.app/"

  auto_updates true
  depends_on macos: :sonoma

  app "Remige.app"
end
