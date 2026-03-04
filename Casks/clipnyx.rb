cask "clipnyx" do
  version "1.0.0"
  sha256 "5bcfe8293d3f4c1a1ccc68111b548fdd90fb951f8fe7e8e19710faac72e4e113"

  url "https://github.com/sawada-sh/clipboard-mac/releases/download/v#{version}/Clipnyx.dmg"
  name "Clipnyx"
  desc "Clipboard history manager for macOS menu bar"
  homepage "https://github.com/sawada-sh/clipboard-mac"

  depends_on macos: ">= :sequoia"

  app "Clipnyx.app"

  zap trash: [
    "~/Library/Application Support/Clipnyx",
    "~/Library/Preferences/com.himatsubu.Clipnyx.plist",
  ]
end
