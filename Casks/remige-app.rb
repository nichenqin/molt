cask "remige-app" do
  version "0.3.1"
  sha256 "5a525f23f606e9fa6592dd7d7114fb9ebfd1a5d722be5e63404d5ff2d5ef4719"

  url "https://github.com/nichenqin/remige/releases/download/v0.3.1/Remige-macos.dmg"
  name "Remige"
  desc "Every update in one place"
  homepage "https://remige.app/"

  auto_updates true
  depends_on macos: :sonoma

  app "Remige.app"
end
