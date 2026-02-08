class GitNativeIssue < Formula
  desc "Distributed issue tracking system built on Git"
  homepage "https://github.com/remenoscodes/git-native-issue"
  url "https://github.com/remenoscodes/git-native-issue/releases/download/v1.0.2/git-native-issue-v1.0.2.tar.gz"
  sha256 "e0b0fe2bee4c5ae8afe487e0c719706be17aacbcf5ca13caab6a0946022144a1"
  license "GPL-2.0-only"
  version "1.0.2"

  depends_on "git"

  def install
    # Install binaries
    bin.install Dir["bin/*"]

    # Install man pages if present
    man1.install Dir["doc/*.1"] if Dir.exist?("doc")

    # Install documentation
    doc.install "README.md", "LICENSE", "ISSUE-FORMAT.md"
  end

  test do
    system "#{bin}/git-issue", "version"
    assert_match "1.0.2", shell_output("#{bin}/git-issue version")
  end
end
