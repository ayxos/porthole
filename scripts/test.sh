#!/usr/bin/env bash
# Compiles the app's non-UI sources with Tests/PortholeTests/main.swift into a
# test runner and executes it. Like build.sh, it calls swiftc by path, so it
# works with only the Command Line Tools and before the Xcode license is accepted.
set -euo pipefail
cd "$(dirname "$0")/.."

XCODE_DEV="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || true)}"
CLT="/Library/Developer/CommandLineTools"
if [ -x "$XCODE_DEV/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc" ]; then
  SWIFTC="$XCODE_DEV/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
  SDK="$XCODE_DEV/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
elif [ -x "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc" ]; then
  XCODE_DEV="/Applications/Xcode.app/Contents/Developer"
  SWIFTC="$XCODE_DEV/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
  SDK="$XCODE_DEV/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
elif [ -x "$CLT/usr/bin/swiftc" ]; then
  SWIFTC="$CLT/usr/bin/swiftc"
  SDK="$CLT/SDKs/MacOSX.sdk"
else
  echo "No Swift toolchain found. Install Xcode, or run: xcode-select --install" >&2
  exit 1
fi

# Everything that does not import AppKit or SwiftUI.
SOURCES=(
  Sources/Porthole/Models.swift
  Sources/Porthole/KnownServices.swift
  Sources/Porthole/ProcessKnowledge.swift
  Sources/Porthole/ProcessDetails.swift
  Sources/Porthole/ProcessInspector.swift
  Sources/Porthole/PortScanner.swift
  Sources/Porthole/Format.swift
  Sources/Porthole/Shell.swift
  Sources/Porthole/UpdateChecker.swift
)

OUT=".build/tests"
mkdir -p "$OUT"
echo "▸ compiling tests"
"$SWIFTC" -sdk "$SDK" -target "$(uname -m)-apple-macosx14.0" -module-name PortholeTests \
  "${SOURCES[@]}" Tests/PortholeTests/main.swift -o "$OUT/porthole-tests"
"$OUT/porthole-tests"
