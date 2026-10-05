#!/usr/bin/env bash
# Builds Porthole.app into ./dist without SwiftPM or xcrun, so it works even
# when the Xcode license has not been accepted yet.
#
#   scripts/build.sh            build only
#   scripts/build.sh --run      build and (re)launch
#   scripts/build.sh --install  build, copy to /Applications and launch
#
# ARCHS="arm64 x86_64" scripts/build.sh builds a universal binary (CI does this
# for releases). The default is the host architecture only, which is faster.
# SIGN_IDENTITY="Developer ID Application: …" signs with the hardened runtime,
# ready for notarization. The default is an ad hoc signature.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Porthole"
BUNDLE_ID="com.ayxos.porthole"
DIST="dist/$APP_NAME.app"
OUT=".build/porthole"
ARCH="$(uname -m)"
read -r -a ARCH_LIST <<< "${ARCHS:-$ARCH}"
mkdir -p "$OUT"

# ---------------------------------------------------------------------------
# Locate a toolchain by path. The /usr/bin shims (swift, swiftc, xcrun) refuse
# to run until `sudo xcodebuild -license accept`; the real binaries do not.
# The SwiftUI macro plugin (@State and friends) only ships inside Xcode on
# recent SDKs, so Xcode is preferred when it is installed.
# ---------------------------------------------------------------------------
XCODE_DEV="${DEVELOPER_DIR:-}"
if [ ! -x "$XCODE_DEV/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc" ]; then
  SELECTED="$(xcode-select -p 2>/dev/null || true)"   # works without the license, unlike xcrun
  if [ -x "$SELECTED/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc" ]; then
    XCODE_DEV="$SELECTED"
  else
    XCODE_DEV="/Applications/Xcode.app/Contents/Developer"
  fi
fi
CLT="/Library/Developer/CommandLineTools"
PLUGIN_FLAGS=()
if [ -x "$XCODE_DEV/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc" ]; then
  TOOLCHAIN="$XCODE_DEV/Toolchains/XcodeDefault.xctoolchain"
  SDK="$XCODE_DEV/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
  PLUGIN_FLAGS+=(-plugin-path "$XCODE_DEV/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins")
  PLUGIN_FLAGS+=(-plugin-path "$TOOLCHAIN/usr/lib/swift/host/plugins")
elif [ -x "$CLT/usr/bin/swiftc" ]; then
  TOOLCHAIN="$CLT"
  SDK="$CLT/SDKs/MacOSX.sdk"
  PLUGIN_FLAGS+=(-plugin-path "$CLT/usr/lib/swift/host/plugins")
else
  echo "No Swift toolchain found. Install Xcode, or run: xcode-select --install" >&2
  exit 1
fi
SWIFTC="$TOOLCHAIN/usr/bin/swiftc"

SLICES=()
for arch in "${ARCH_LIST[@]}"; do
  echo "▸ compiling $APP_NAME ($arch) with $SWIFTC"
  "$SWIFTC" -O -parse-as-library \
    -sdk "$SDK" -target "$arch-apple-macosx14.0" \
    -module-name "$APP_NAME" "${PLUGIN_FLAGS[@]}" \
    Sources/Porthole/*.swift Sources/Porthole/Views/*.swift \
    -o "$OUT/$APP_NAME-$arch"
  SLICES+=("$OUT/$APP_NAME-$arch")
done
lipo -create "${SLICES[@]}" -output "$OUT/$APP_NAME"

if [ ! -f Resources/AppIcon.icns ]; then
  echo "▸ rendering Resources/AppIcon.icns"
  "$SWIFTC" -O -sdk "$SDK" -target "$ARCH-apple-macosx14.0" -module-name MakeIcon \
    scripts/make-icon.swift -o "$OUT/make-icon"
  "$OUT/make-icon" Resources/AppIcon.icns
fi

echo "▸ assembling $DIST"
rm -rf "$DIST"
mkdir -p "$DIST/Contents/MacOS" "$DIST/Contents/Resources"
cp "$OUT/$APP_NAME" "$DIST/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$DIST/Contents/Info.plist"
cp Resources/AppIcon.icns "$DIST/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$DIST/Contents/PkgInfo"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
if [ "$SIGN_IDENTITY" = "-" ]; then
  codesign --force --sign - --identifier "$BUNDLE_ID" "$DIST"
else
  codesign --force --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" --options runtime --timestamp "$DIST"
fi
echo "✓ built $DIST"

case "${1:-}" in
  --run)
    pkill -x "$APP_NAME" 2>/dev/null || true
    sleep 0.3
    open "$DIST"
    echo "✓ launched, look for the porthole in the menu bar"
    ;;
  --install)
    pkill -x "$APP_NAME" 2>/dev/null || true
    rm -rf "/Applications/$APP_NAME.app"
    ditto "$DIST" "/Applications/$APP_NAME.app"
    open "/Applications/$APP_NAME.app"
    echo "✓ installed to /Applications/$APP_NAME.app and launched"
    ;;
esac
