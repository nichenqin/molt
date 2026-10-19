cask "molt-app" do
  version "0.2.0"
  sha256 "858d194ea527c2b0b9c7074bca7273d05cf55cbe323f00b5a9765c24abb854f6"

  url "https://github.com/nichenqin/molt/releases/download/v0.2.0/Molt-macos.dmg"
  name "Molt"
  desc "Every update in one place"
  homepage "https://molt-site-five.vercel.app/"

  auto_updates true
  depends_on macos: :sonoma

  app "Molt.app"
end
