# Homebrew cask that installs the prebuilt Porthole.app from the latest release.
# It lives in ayxos/homebrew-tap as Casks/porthole.rb; the release workflow
# updates version and sha256 there on every tag.
cask "porthole" do
  version "1.0.0"
  sha256 "a9fba8177b6d8b7e405abbc51f8554fb20f0d95b79b514c25a26ed8710bbd266"

  url "https://github.com/ayxos/porthole/releases/download/v#{version}/Porthole.zip"
  name "Porthole"
  desc "Menu bar app that shows listening ports and their processes"
  homepage "https://github.com/ayxos/porthole"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "Porthole.app"
  binary "#{appdir}/Porthole.app/Contents/MacOS/Porthole", target: "porthole"

  uninstall quit: "com.ayxos.porthole"

  zap trash: "~/Library/Preferences/com.ayxos.porthole.plist"

  caveats <<~EOS
    Porthole is signed ad hoc and not notarized. If macOS says it is damaged, run:
      xattr -d com.apple.quarantine #{appdir}/Porthole.app
    or reinstall with: brew reinstall --cask --no-quarantine porthole
  EOS
end
