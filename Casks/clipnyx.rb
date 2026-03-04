cask "clipnyx" do
  version "1.1.1"
  sha256 "183a9359198d131711bf9424632d2e4075956212b9098501c98243b1a63768a6"

  url "https://github.com/sawasige/clipboard-mac/releases/download/v#{version}/Clipnyx.dmg"
  name "Clipnyx"
  desc "Clipboard history manager for macOS menu bar"
  homepage "https://github.com/sawasige/clipboard-mac"

  depends_on macos: ">= :sequoia"

  app "Clipnyx.app"

  zap trash: [
    "~/Library/Application Support/Clipnyx",
    "~/Library/Preferences/com.himatsubu.Clipnyx.plist",
  ]
end
