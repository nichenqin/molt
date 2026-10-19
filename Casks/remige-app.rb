cask "remige-app" do
  version "0.3.1"
  sha256 "b7e7a7c58a119154a602604985ad41cf0d1c1b8fbbbe5c1b104875e4a71f8fa8"

  url "https://github.com/nichenqin/remige/releases/download/v#{version}/Remige-macos.dmg"
  name "Remige"
  desc "Every update in one place"
  homepage "https://remige.app/"

  livecheck do
    url "https://github.com/nichenqin/remige"
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :sonoma

  app "Remige.app"

  zap trash: [
    "~/.config/remige",
    "~/Library/Caches/app.remige",
    "~/Library/HTTPStorages/app.remige",
    "~/Library/Preferences/app.remige.plist",
    "~/Library/Saved Application State/app.remige.savedState",
    # Bundle identifier used before the move to app.remige.
    "~/Library/Caches/com.nichenqin.remige",
    "~/Library/HTTPStorages/com.nichenqin.remige",
    "~/Library/Preferences/com.nichenqin.remige.plist",
    "~/Library/Saved Application State/com.nichenqin.remige.savedState",
  ]
end
