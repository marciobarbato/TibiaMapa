#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SIGN_IDENTITY:?Defina SIGN_IDENTITY com seu Developer ID Application}"
: "${NOTARY_PROFILE:?Defina NOTARY_PROFILE com o perfil do Keychain}"
RELEASE_DIR="${RELEASE_DIR:-$(mktemp -d /private/tmp/TibiaMapa-release.XXXXXX)}"
mkdir -p "$RELEASE_DIR"
xcodebuild -project TibiaMapa.xcodeproj -scheme TibiaMapa -configuration Release \
  -derivedDataPath "$RELEASE_DIR/build" ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO build
APP="$RELEASE_DIR/build/Build/Products/Release/TibiaMapa.app"
xattr -cr "$APP"
codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP/Contents/Resources/ZIPFoundation_ZIPFoundation.bundle"
codesign --force --options runtime --timestamp --entitlements TibiaMapa/TibiaMapa.entitlements --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
ditto -c -k --keepParent "$APP" "$RELEASE_DIR/TibiaMapa.zip"
xcrun notarytool submit "$RELEASE_DIR/TibiaMapa.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
mkdir -p "$RELEASE_DIR/dmg"
ditto "$APP" "$RELEASE_DIR/dmg/TibiaMapa.app"
ln -sfn /Applications "$RELEASE_DIR/dmg/Applications"
cp LEIA-ME.txt "$RELEASE_DIR/dmg/LEIA-ME.txt"
hdiutil create -volname TibiaMapa -srcfolder "$RELEASE_DIR/dmg" -ov -format UDZO "$RELEASE_DIR/TibiaMapa-2.2.dmg"
codesign --timestamp --sign "$SIGN_IDENTITY" "$RELEASE_DIR/TibiaMapa-2.2.dmg"
xcrun notarytool submit "$RELEASE_DIR/TibiaMapa-2.2.dmg" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$RELEASE_DIR/TibiaMapa-2.2.dmg"
xcrun stapler validate "$RELEASE_DIR/TibiaMapa-2.2.dmg"
spctl --assess --type execute --verbose=2 "$APP"
printf 'DMG: %s\n' "$RELEASE_DIR/TibiaMapa-2.2.dmg"
