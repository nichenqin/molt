class Molt < Formula
  desc "Every macOS update in one place: brew, npm, apps, and CLI tools"
  homepage "https://molt-site-five.vercel.app/"
  url "https://github.com/nichenqin/molt/releases/download/v0.2.0/molt-cli"
  version "0.2.0"
  sha256 "51e1c4d4a391d0f2df72f4d48898530ef8bb94790b20e71668faff1dc4525482"
  license "MIT"

  def install
    bin.install "molt-cli" => "molt"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/molt version")
  end
end
