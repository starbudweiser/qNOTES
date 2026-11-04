#!/bin/bash
# Compile qNOTES.app (release), avec son icône, ses langues et la signature stable.
# Usage : ./build_app.sh   (produit ./qNOTES.app ; NO_INSTALL=1 pour ne pas l'installer)
set -euo pipefail
cd "$(dirname "$0")"

TOOLS=/Volumes/SKYRIM/TOOLS
DEST="${QNOTES_INSTALL_DIR:-$HOME/Applications/Applications Personnelles}"
VERSION="${VERSION:-1.0.0}"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

# Socle vit hors de l'arborescence parcourue par sync_apps.sh : copie reprise à chaque build.
if [ -f "$TOOLS/DESIGN/Socle/swift/Socle.swift" ]; then
    cp "$TOOLS/DESIGN/Socle/swift/Socle.swift" Sources/qNOTES/Socle.swift
fi

if [ ! -f assets/qNOTES.icns ]; then
    mkdir -p assets
    TMP="$(mktemp -d)"
    swift scripts/make_icon.swift "$TMP/icon.png"
    mkdir "$TMP/qNOTES.iconset"
    for s in 16 32 128 256 512; do
        sips -z $s $s "$TMP/icon.png" --out "$TMP/qNOTES.iconset/icon_${s}x${s}.png" >/dev/null
        sips -z $((s*2)) $((s*2)) "$TMP/icon.png" --out "$TMP/qNOTES.iconset/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$TMP/qNOTES.iconset" -o assets/qNOTES.icns
    cp "$TMP/icon.png" assets/qNOTES.png
    rm -rf "$TMP"
fi

swift build -c release
BIN="$(swift build -c release --show-bin-path)/qNOTES"

APP=qNOTES.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/qNOTES"
cp assets/qNOTES.icns "$APP/Contents/Resources/"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>qNOTES</string>
    <key>CFBundleDisplayName</key><string>qNOTES</string>
    <key>CFBundleIdentifier</key><string>fr.stephan.qnotes</string>
    <key>CFBundleExecutable</key><string>qNOTES</string>
    <key>CFBundleIconFile</key><string>qNOTES</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>fr</string><string>en</string><string>es</string><string>it</string></array>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 Starbudweiser</string>
</dict>
</plist>
PLIST

if [ -x "$TOOLS/MAC/_tools/sign_app.sh" ]; then
    "$TOOLS/MAC/_tools/sign_app.sh" "$APP"
else
    codesign --force --deep --sign - "$APP"   # signature ad hoc hors de ma machine
fi

if [ "${NO_INSTALL:-0}" != 1 ]; then
    mkdir -p "$DEST"
    osascript -e 'tell application id "fr.stephan.qnotes" to quit' 2>/dev/null || true
    rm -rf "$DEST/$APP"
    cp -R "$APP" "$DEST/"
    echo "Installé : $DEST/$APP"
fi
