class Remige < Formula
  desc "Every macOS update in one place: brew, npm, apps, and CLI tools"
  homepage "https://remige.vercel.app/"
  url "https://github.com/nichenqin/remige/releases/download/v0.3.0/remige-cli"
  version "0.3.0"
  sha256 "71a8db1128606eaa533d8827900a759150aaa16d134e40d76617f3ea8c949803"
  license "MIT"

  def install
    bin.install "remige-cli" => "remige"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/remige version")
  end
end
