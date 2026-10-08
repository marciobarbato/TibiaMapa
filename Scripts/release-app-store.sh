#!/bin/bash
# Prepare a local App Store Connect package. Never uploads or submits for review.
set -euo pipefail
cd "$(dirname "$0")/.."
out="${1:?Usage: release-app-store.sh OUTPUT_DIR [--allow-provisioning-updates]}"
[[ ! -e "$out" ]] || { echo 'Use a new output directory.' >&2; exit 2; }
provisioning=()
if [[ "${2:-}" == '--allow-provisioning-updates' ]]; then provisioning=(-allowProvisioningUpdates); fi
mkdir -p "$out"
out="$(cd "$out" && pwd)"
xcodebuild -project TibiaMapa.xcodeproj -scheme TibiaMapa -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$out/build" \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  ${provisioning[@]+"${provisioning[@]}"} -archivePath "$out/TibiaMapa.xcarchive" archive > "$out/archive.log" 2>&1 || { tail -50 "$out/archive.log"; exit 1; }
app="$out/TibiaMapa.xcarchive/Products/Applications/TibiaMapa.app"
xattr -cr "$app"
python3 Scripts/validate-app-store.py "$app" > "$out/archive-validation.txt"
xcodebuild -exportArchive -archivePath "$out/TibiaMapa.xcarchive" \
  -exportPath "$out/export" -exportOptionsPlist Scripts/ExportOptions-AppStore.plist \
  ${provisioning[@]+"${provisioning[@]}"} > "$out/export.log" 2>&1 || { tail -50 "$out/export.log"; exit 1; }
pkg=("$out/export/"*.pkg)
[[ ${#pkg[@]} -eq 1 && -f "${pkg[0]}" ]]
pkgutil --check-signature "${pkg[0]}" > "$out/package-signature.txt"
pkgutil --expand-full "${pkg[0]}" "$out/expanded"
python3 Scripts/validate-app-store.py "$out/expanded/barbato.TibiaMapa.pkg/Payload/TibiaMapa.app" --distribution > "$out/distribution-validation.txt"
shasum -a 256 "${pkg[0]}" > "$out/package-sha256.txt"
echo "Prepared locally: ${pkg[0]}"
