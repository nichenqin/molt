class Remige < Formula
  desc "Every macOS update in one place: brew, npm, apps, and CLI tools"
  homepage "https://remige.app/"
  url "https://github.com/nichenqin/remige/releases/download/v#{version}/remige-cli"
  version "0.3.1"
  sha256 "efdfcef078b50526f18dc1d68446b22503a293c8c9486217fa5e297216754e6b"
  license "MIT"

  def install
    bin.install "remige-cli" => "remige"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/remige version")
  end
end
