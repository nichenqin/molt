class Remige < Formula
  desc "Every macOS update in one place: brew, npm, apps, and CLI tools"
  homepage "https://remige.app/"
  url "https://github.com/nichenqin/remige/releases/download/v#{version}/remige-cli"
  version "0.4.0"
  sha256 "c5a59f253804b9746772ec73ac14bc61105b6d7a8eb2dfdcf657c95dabe59e61"
  license "MIT"

  livecheck do
    url "https://github.com/nichenqin/remige"
    strategy :github_latest
  end

  def install
    bin.install "remige-cli" => "remige"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/remige version")
  end
end
