class Remige < Formula
  desc "Every macOS update in one place: brew, npm, apps, and CLI tools"
  homepage "https://remige.vercel.app/"
  url "https://github.com/nichenqin/remige/releases/download/v0.3.0/remige-cli"
  version "0.3.0"
  sha256 "35470a6b1125e104eb5783877d0be8f96982a67501f6e92a0294d43df58f7b75"
  license "MIT"

  def install
    bin.install "remige-cli" => "remige"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/remige version")
  end
end
