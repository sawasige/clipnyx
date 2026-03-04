cask "clipnyx" do
  version "1.1.3"
  sha256 "a1912426fd97be18af86ebbd02a00cadc40d288c34b4cf35f31a873a35a4d21a"

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
