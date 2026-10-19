cask "molt-app" do
  version "0.2.0"
  sha256 "ace1b5945594cf45c9c83e81fe6bbf6df19d5cbb53aa95f7b4b17bc484cccb43"

  url "https://github.com/nichenqin/molt/releases/download/v0.2.0/Molt-macos.dmg"
  name "Molt"
  desc "Every update in one place"
  homepage "https://nichenqin.github.io/molt/"

  auto_updates true
  depends_on macos: :sonoma

  app "Molt.app"
end
