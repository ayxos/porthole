# Homebrew formula that builds Porthole from source.
#
# To offer it from your own tap, create a GitHub repo named `homebrew-tap`,
# copy this file to `Formula/porthole.rb` in it, and users can run:
#
#   brew install --HEAD ayxos/tap/porthole
#
# Building from source sidesteps Gatekeeper's warning about unnotarized
# downloads, because the app is signed ad hoc on the user's own machine.
class Porthole < Formula
  desc "Menu bar app that shows listening ports and their processes"
  homepage "https://github.com/ayxos/porthole"
  license "MIT"
  head "https://github.com/ayxos/porthole.git", branch: "main"

  depends_on xcode: ["15.0", :build]
  depends_on macos: :sonoma

  def install
    system "scripts/build.sh"
    prefix.install "dist/Porthole.app"
    bin.write_exec_script "#{prefix}/Porthole.app/Contents/MacOS/Porthole"
  end

  def caveats
    <<~EOS
      Porthole.app is in #{prefix}. Link it into /Applications so Launch at Login works:
        ln -sf #{prefix}/Porthole.app /Applications/Porthole.app
      The CLI is available as `Porthole --list`.
    EOS
  end

  test do
    assert_match "Porthole", shell_output("#{bin}/Porthole --help")
  end
end
