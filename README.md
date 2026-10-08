# TibiaMapa

TibiaMapa is a free, native macOS app for updating Tibia maps with packages from [TibiaMaps.io](https://tibiamaps.io/downloads), preserving personal markers, and exploring the minimap without launching the game. Marcio Barbato built it for the Mac Tibia community. **Proudly made in Brasil.**

This is an independent project with no affiliation with CipSoft or TibiaMaps.io. Tibia and its graphical elements belong to CipSoft GmbH. Map data is provided by TibiaMaps.io. See the [third-party notices](TibiaMapa/ThirdPartyNotices.txt).

## Features

- Update the minimap using the five map styles available from TibiaMaps.io.
- Preserve local markers by default, with a separate option to back up the current maps before updating.
- Restore backups and browse normal and private markers in a searchable table.
- Explore local maps by coordinate and floor; double-click a marker to open its location in the viewer.
- Search, sort, and filter markers by source and column without losing the current search when returning from the map.
- Show all markers, game originals, private markers, or none in the viewer; change floors with Page Up and Page Down.
- Use the interface in English, Brazilian Portuguese, or Polish. By default, the app follows macOS language preferences.
- Use every feature for free, with no account, ads, in-app purchases, or usage analytics.

## Install and use

TibiaMapa requires macOS 13 or later and supports Apple Silicon and Intel Macs. Download the signed, notarized DMG from [GitHub Releases](https://github.com/marciobarbato/TibiaMapa/releases). Version 2.2 has been submitted for Mac App Store review; version 2.3 is available as a direct download. The [support site](https://marciobarbato.github.io/TibiaMapa/) provides contact information, privacy details, and credits. To build locally, open `TibiaMapa.xcodeproj` in Xcode, select the `TibiaMapa` scheme, and run the app.

On first launch, use the macOS folder picker to select the Tibia installation's **Resources** folder, which contains `minimap`. Selecting `minimap` alone does not give the sandbox enough access to replace maps safely. Close both the Tibia client and launcher before updating or restoring maps. We recommend creating a backup before the first update of your real maps.

With **Preserve my markers** enabled, existing `minimapmarkers.bin` and `privateminimapmarkers.bin` files remain unchanged. Package markers are imported only when the normal marker file does not already exist. The update keeps local map images absent from the package; it does not merge pixels or markers. Disabling preservation may replace or remove both existing marker files, depending on the selected package. Restoring a backup replaces the current content with the selected backup.

## Privacy

Maps, markers, preferences, and backups stay on the user's Mac. The app does not upload markers or collect usage data. Downloading map packages uses HTTPS and makes ordinary connections to TibiaMaps.io services, which may log connection data under their own policies. See the [privacy policy](https://marciobarbato.github.io/TibiaMapa/#privacidade).

## Development

The app uses SwiftUI and AppKit. Version 2.3 runs in the App Sandbox, with access to a folder chosen by the user and network permission to download maps. Downloads and file operations are validated, and the minimap folder is replaced atomically.

```sh
xcodebuild -project TibiaMapa.xcodeproj -scheme TibiaMapa \
  -derivedDataPath /private/tmp/TibiaMapa-build \
  -only-testing:TibiaMapaTests CODE_SIGN_IDENTITY=- test
```

Scripts in `Scripts/` prepare Developer ID and Mac App Store builds. Signing and notarization require your own certificates and credentials, kept outside this repository.

## Credits and rights

- **Tibia and graphical symbols:** © CipSoft GmbH.
- **Map data:** [TibiaMaps.io / tibia-map-data](https://github.com/tibiamaps/tibia-map-data), MIT License, © Mathias Bynens. Maps are downloaded at runtime and are not bundled with the source or installer.
- **ZIPFoundation:** MIT License, © Thomas Zoechling.
- **TibiaMapa:** developed by Marcio Barbato.

The TibiaMapa source is public for inspection. No license to reuse its original code has been granted at this time. Third-party licenses and rights in graphical elements are separate. Publishing this repository does not grant rights to Tibia, its symbols, or its trademarks.
