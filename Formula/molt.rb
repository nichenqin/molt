class Molt < Formula
  desc "Every macOS update in one place: brew, npm, apps, and CLI tools"
  homepage "https://molt-site-five.vercel.app/"
  url "https://github.com/nichenqin/molt/releases/download/v0.2.0/molt-cli"
  version "0.2.0"
  sha256 "dd9cbad7e7a31d1ae2be2516117147e0634b85eb2a4181475639fbdfa0bbe0a9"
  license "MIT"

  def install
    bin.install "molt-cli" => "molt"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/molt version")
  end
end
