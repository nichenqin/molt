class Remige < Formula
  desc "Every macOS update in one place: brew, npm, apps, and CLI tools"
  homepage "https://remige.app/"
  url "https://github.com/nichenqin/remige/releases/download/v0.3.1/remige-cli"
  version "0.3.1"
  sha256 "e19fedc70bb2e17174b7ee43b24ccc8f113370ce1c2b36112a974d9302cd3a13"
  license "MIT"

  def install
    bin.install "remige-cli" => "remige"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/remige version")
  end
end
