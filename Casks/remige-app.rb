cask "remige-app" do
  version "0.3.0"
  sha256 "07d53380dcc4330974f67cb62c9ba4bc706c9a73d83f2c67d1d41c50c6cca5c7"

  url "https://github.com/nichenqin/remige/releases/download/v0.3.0/Remige-macos.dmg"
  name "Remige"
  desc "Every update in one place"
  homepage "https://remige.vercel.app/"

  auto_updates true
  depends_on macos: :sonoma

  app "Remige.app"
end
