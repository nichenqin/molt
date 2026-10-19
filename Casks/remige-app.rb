cask "remige-app" do
  version "0.3.0"
  sha256 "d51ff36990e7f2ea572dcd0a407cc42563fb65e9b1e16ffcc8a498d3d84ee6c4"

  url "https://github.com/nichenqin/remige/releases/download/v0.3.0/Remige-macos.dmg"
  name "Remige"
  desc "Every update in one place"
  homepage "https://remige.vercel.app/"

  auto_updates true
  depends_on macos: :sonoma

  app "Remige.app"
end
