cask "remige-app" do
  version "0.4.0"
  sha256 "babbb73b88c31da541a381ee421a9e977a7484376f2a9dfd9c81c5e11e6ead61"

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
