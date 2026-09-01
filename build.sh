#!/bin/bash
# OmSaver — build du .saver sans Xcode :
#   swiftc -emit-object → clang -bundle (Mach-O MH_BUNDLE, requis par
#   legacyScreenSaver pour charger NSPrincipalClass) → bundle .saver.
#   ./build.sh          → build/OmSaver.saver
#   ./build.sh install  → + copie dans ~/Library/Screen Savers
set -euo pipefail
cd "$(dirname "$0")"

VERSION=1.0
BUILD=build
SAVER="$BUILD/OmSaver.saver"
mkdir -p "$BUILD/obj"

echo "→ compilation (universel arm64 + x86_64)…"
for ARCH in arm64 x86_64; do
  swiftc -O -parse-as-library -target ${ARCH}-apple-macos13 \
    -module-name OmSaver -emit-object \
    -o "$BUILD/obj/OmSaverView-$ARCH.o" Sources/OmSaverView.swift
  clang -bundle -target ${ARCH}-apple-macos13 \
    -o "$BUILD/obj/OmSaver-$ARCH" "$BUILD/obj/OmSaverView-$ARCH.o" \
    -framework ScreenSaver -framework AppKit -framework Foundation \
    -L /usr/lib/swift \
    -L "$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx"
done
lipo -create -output "$BUILD/OmSaverBin" "$BUILD/obj/OmSaver-arm64" "$BUILD/obj/OmSaver-x86_64"

echo "→ bundle…"
rm -rf "$SAVER"
mkdir -p "$SAVER/Contents/MacOS"
cp "$BUILD/OmSaverBin" "$SAVER/Contents/MacOS/OmSaver"
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
  <key>NSHumanReadableCopyright</key><string>© 2026 Stranix — MIT license</string>
</dict>
</plist>
PLIST

# signature stable (Gatekeeper est plus détendu pour les .saver mais autant signer)
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
  | awk -F'"' '/Apple Development/ {print $2; exit}')
if [ -n "$IDENTITY" ]; then
  codesign --force --sign "$IDENTITY" "$SAVER"
else
  codesign --force --sign - "$SAVER"
fi

if [ "${1:-}" = "install" ]; then
  rm -rf "$HOME/Library/Screen Savers/OmSaver.saver"
  cp -R "$SAVER" "$HOME/Library/Screen Savers/"
  echo "✓ installé — Réglages Système → Économiseur d'écran → OmSaver"
else
  echo "✓ $SAVER"
fi
