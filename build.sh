#!/bin/bash
# OmSaver — build du .saver sans Xcode :
#   swiftc -emit-object → clang -bundle (Mach-O MH_BUNDLE, requis par
#   legacyScreenSaver pour charger NSPrincipalClass) → bundle .saver.
#   ./build.sh          → build/OmSaver.saver
#   ./build.sh install  → + copie dans ~/Library/Screen Savers
#
# ── POURQUOI CE PIPELINE ? ──────────────────────────────────────────────────
# Un .saver n'est PAS un exécutable : c'est un plugin que legacyScreenSaver
# charge dynamiquement (dlopen). Le binaire doit donc être un Mach-O de type
# MH_BUNDLE — ce que `swiftc` seul ne sait pas produire proprement. D'où les
# deux étapes, comme en C (compilation puis édition de liens séparées) :
#   1. swiftc -emit-object : Swift → fichier objet .o (pas de linkage)
#   2. clang -bundle       : .o → binaire MH_BUNDLE, lié aux frameworks
# Et un « bundle » macOS n'est qu'un dossier avec une structure convenue :
#   OmSaver.saver/Contents/MacOS/OmSaver   ← le binaire
#   OmSaver.saver/Contents/Info.plist      ← la carte d'identité (XML)
# Le Finder l'affiche comme un fichier unique grâce à l'extension .saver.
set -euo pipefail
cd "$(dirname "$0")"

VERSION=1.0
BUILD=build
SAVER="$BUILD/OmSaver.saver"
mkdir -p "$BUILD/obj"

# Binaire « universel » : on compile deux fois (Apple Silicon + Intel), puis
# lipo colle les deux Mach-O dans un seul fichier ; macOS choisit sa tranche.
echo "→ compilation (universel arm64 + x86_64)…"
for ARCH in arm64 x86_64; do
  # -parse-as-library : pas de point d'entrée main() — c'est un plugin,
  #   legacyScreenSaver instancie la classe, personne ne « lance » ce code.
  # -target ...-macos13 : plancher de compatibilité (= LSMinimumSystemVersion).
  swiftc -O -parse-as-library -target ${ARCH}-apple-macos13 \
    -module-name OmSaver -emit-object \
    -o "$BUILD/obj/OmSaverView-$ARCH.o" Sources/OmSaverView.swift
  # -bundle : produit un Mach-O MH_BUNDLE (chargeable par dlopen), pas un
  #   exécutable. Les -framework lient ScreenSaver/AppKit/Foundation, et les
  #   -L indiquent où trouver les bibliothèques runtime de Swift.
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
# L'Info.plist est généré ici même — pas de projet Xcode, pas de fichier à
# part. Les clés qui comptent :
#   CFBundleIdentifier : identité unique du plugin pour le système
#   NSPrincipalClass   : la classe que legacyScreenSaver doit instancier ;
#                        doit correspondre au @objc(OmSaverView) du source
#   CFBundleShortVersionString : relue à l'exécution par le footer du saver
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
# On préfère un certificat « Apple Development » du trousseau s'il existe ;
# sinon `codesign --sign -` fait une signature ad hoc (sans certificat),
# suffisante pour un usage local sur sa propre machine.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
  | awk -F'"' '/Apple Development/ {print $2; exit}')
if [ -n "$IDENTITY" ]; then
  codesign --force --sign "$IDENTITY" "$SAVER"
else
  codesign --force --sign - "$SAVER"
fi

# Installation par simple copie : les savers de l'utilisateur vivent dans
# ~/Library/Screen Savers (ceux du système dans /System/Library/Screen Savers).
if [ "${1:-}" = "install" ]; then
  rm -rf "$HOME/Library/Screen Savers/OmSaver.saver"
  cp -R "$SAVER" "$HOME/Library/Screen Savers/"
  echo "✓ installé — Réglages Système → Économiseur d'écran → OmSaver"
else
  echo "✓ $SAVER"
fi
