#!/bin/bash
# OmSaver: building the .saver without Xcode.
#   swiftc -emit-object -> clang -bundle (Mach-O MH_BUNDLE, required by
#   legacyScreenSaver to load NSPrincipalClass) -> .saver bundle.
#   ./build.sh          -> build/OmSaver.saver
#   ./build.sh install  -> also copies it to ~/Library/Screen Savers
#
# -- WHY THIS PIPELINE? ------------------------------------------------------
# A .saver is NOT an executable: it is a plugin that legacyScreenSaver loads
# dynamically (dlopen). The binary must therefore be a Mach-O of type
# MH_BUNDLE, which `swiftc` alone cannot produce cleanly. Hence the two
# steps, as in C (compile, then link separately):
#   1. swiftc -emit-object : Swift -> .o object file (no linking)
#   2. clang -bundle       : .o -> MH_BUNDLE binary, linked to the frameworks
# And a macOS "bundle" is nothing more than a folder with an agreed layout:
#   OmSaver.saver/Contents/MacOS/OmSaver   <- the binary
#   OmSaver.saver/Contents/Info.plist      <- the identity card (XML)
# The Finder shows it as a single file thanks to the .saver extension.
set -euo pipefail
cd "$(dirname "$0")"

VERSION=1.1
BUILD=build
SAVER="$BUILD/OmSaver.saver"
mkdir -p "$BUILD/obj"

# "Universal" binary: compile twice (Apple Silicon + Intel), then lipo glues
# both Mach-O files into one; macOS picks its own slice.
echo "-> compiling (universal arm64 + x86_64)..."
for ARCH in arm64 x86_64; do
  # -parse-as-library : no main() entry point. This is a plugin:
  #   legacyScreenSaver instantiates the class, nobody "launches" this code.
  # -target ...-macos13 : compatibility floor (= LSMinimumSystemVersion).
  swiftc -O -parse-as-library -target ${ARCH}-apple-macos13 \
    -module-name OmSaver -emit-object \
    -o "$BUILD/obj/OmSaverView-$ARCH.o" Sources/OmSaverView.swift
  # -bundle : produces an MH_BUNDLE Mach-O (loadable with dlopen), not an
  #   executable. The -framework flags link ScreenSaver/AppKit/Foundation,
  #   the -L flags say where the Swift runtime libraries live.
  clang -bundle -target ${ARCH}-apple-macos13 \
    -o "$BUILD/obj/OmSaver-$ARCH" "$BUILD/obj/OmSaverView-$ARCH.o" \
    -framework ScreenSaver -framework AppKit -framework Foundation \
    -L /usr/lib/swift \
    -L "$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx"
done
lipo -create -output "$BUILD/OmSaverBin" "$BUILD/obj/OmSaver-arm64" "$BUILD/obj/OmSaver-x86_64"

echo "-> bundle..."
rm -rf "$SAVER"
mkdir -p "$SAVER/Contents/MacOS"
cp "$BUILD/OmSaverBin" "$SAVER/Contents/MacOS/OmSaver"
# The Info.plist is generated right here: no Xcode project, no separate
# file. The keys that matter:
#   CFBundleIdentifier : unique identity of the plugin for the system
#   NSPrincipalClass   : the class legacyScreenSaver must instantiate;
#                        must match the @objc(OmSaverView) in the source
#   CFBundleShortVersionString : read back at runtime by the saver's footer
cat > "$SAVER/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>OmSaver</string>
  <key>CFBundleIdentifier</key><string>net.stranix.omsaver</string>
  <key>CFBundleName</key><string>OmSaver</string>
  <key>CFBundlePackageType</key><string>BNDL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>NSPrincipalClass</key><string>OmSaverView</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHumanReadableCopyright</key><string>© 2026 Stranix, MIT license</string>
</dict>
</plist>
PLIST

# Stable signature (Gatekeeper is more relaxed with .saver bundles, but let's
# sign anyway). Prefer an "Apple Development" certificate from the keychain
# if there is one; otherwise `codesign --sign -` makes an ad hoc signature
# (no certificate), enough for local use on your own machine.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
  | awk -F'"' '/Apple Development/ {print $2; exit}')
if [ -n "$IDENTITY" ]; then
  codesign --force --sign "$IDENTITY" "$SAVER"
else
  codesign --force --sign - "$SAVER"
fi

# Installing is a plain copy: the user's savers live in ~/Library/Screen Savers
# (the system ones in /System/Library/Screen Savers).
if [ "${1:-}" = "install" ]; then
  rm -rf "$HOME/Library/Screen Savers/OmSaver.saver"
  cp -R "$SAVER" "$HOME/Library/Screen Savers/"
  echo "✓ installed. System Settings > Screen Saver > OmSaver"
else
  echo "✓ $SAVER"
fi
