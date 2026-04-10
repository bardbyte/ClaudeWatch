cask "claudewatch" do
  version "1.0.1"
  sha256 "<SHA256_OF_ZIP>"

  url "https://github.com/bardbyte/ClaudeWatch/releases/download/v#{version}/ClaudeWatch.zip"
  name "ClaudeWatch"
  desc "Monitor and dispatch across multiple Claude Code sessions"
  homepage "https://github.com/bardbyte/ClaudeWatch"

  depends_on macos: ">= :sonoma"

  app "ClaudeWatch.app"

  zap trash: [
    "~/Library/Caches/com.bardbyte.claudewatch",
    "~/Library/Preferences/com.bardbyte.claudewatch.plist",
  ]
end
