import Foundation
import Testing
import AppKit
@testable import TibiaMapa

struct TibiaMapaTests {
    func fixture(_ body: (URL, URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let src = root.appendingPathComponent("source")
        let dst = root.appendingPathComponent("minimap")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
        try body(src, dst, root.appendingPathComponent("backups"))
    }
    var tile: Data { Data([137,80,78,71,13,10,26,10,0,0,0,13,73,72,68,82,0,0,1,0,0,0,1,0]) }
    let name = "Minimap_Color_32000_32000_7.png"
    @Test func preservesBothMarkerFilesAndLocalOnlyTiles() throws {
        try fixture { src, dst, backups in
            try tile.write(to: src.appendingPathComponent(name))
            try Data("downloaded markers".utf8).write(to: src.appendingPathComponent("minimapmarkers.bin"))
            for marker in ["minimapmarkers.bin", "privateminimapmarkers.bin", "future-format.bin"] {
                try Data([0,255,42]).write(to: dst.appendingPathComponent(marker))
            }
            try Data("local exploration".utf8).write(to: dst.appendingPathComponent("Minimap_Color_1_1_7.png"))
            try Data("old".utf8).write(to: dst.appendingPathComponent(name))
            let result = try MapEngine.install(source: src, destination: dst, backups: backups)
            #expect(result.updated == 1)
            #expect(result.preserved == 3)
            #expect(try Data(contentsOf: dst.appendingPathComponent(name)) == tile)
            for marker in ["minimapmarkers.bin", "privateminimapmarkers.bin", "future-format.bin"] {
                #expect(try Data(contentsOf: dst.appendingPathComponent(marker)) == Data([0,255,42]))
            }
            #expect(try Data(contentsOf: result.backup!.appendingPathComponent(name)) == Data("old".utf8))
            #expect(try Data(contentsOf: dst.appendingPathComponent("Minimap_Color_1_1_7.png")) == Data("local exploration".utf8))
        }
    }
    @Test func failureBeforeCommitLeavesOriginalUntouched() throws {
        try fixture { src, dst, backups in
            try tile.write(to: src.appendingPathComponent(name))
            try Data("original".utf8).write(to: dst.appendingPathComponent(name))
            #expect(throws: MapFailure.self) {
                try MapEngine.install(source: src, destination: dst, backups: backups) { throw MapFailure("Tibia aberto") }
            }
            #expect(try Data(contentsOf: dst.appendingPathComponent(name)) == Data("original".utf8))
        }
    }
    @Test func rejectsCorruptedTilesBeforeBackup() throws {
        try fixture { src, dst, backups in
            try Data("bad".utf8).write(to: src.appendingPathComponent(name))
            #expect(throws: MapFailure.self) { try MapEngine.install(source: src, destination: dst, backups: backups) }
            #expect(!FileManager.default.fileExists(atPath: backups.path))
        }
    }
    @Test func rejectsSymlinksAndUnknownDestination() throws {
        try fixture { src, dst, backups in
            try tile.write(to: src.appendingPathComponent(name))
            try FileManager.default.createSymbolicLink(at: dst.appendingPathComponent("minimapmarkers.bin"), withDestinationURL: src.appendingPathComponent(name))
            #expect(throws: MapFailure.self) { try MapEngine.install(source: src, destination: dst, backups: backups) }
            #expect(throws: MapFailure.self) { try MapEngine.destination(src) }
        }
    }
    @Test func importsMarkersOnlyWhenAbsent() throws {
        try fixture { src, dst, backups in
            try tile.write(to: src.appendingPathComponent(name))
            let markers = Data([10, 0])
            try markers.write(to: src.appendingPathComponent("minimapmarkers.bin"))
            _ = try MapEngine.install(source: src, destination: dst, backups: backups)
            #expect(try Data(contentsOf: dst.appendingPathComponent("minimapmarkers.bin")) == markers)
        }
    }
    @Test func backupFailureLeavesOriginalUntouched() throws {
        try fixture { src, dst, backups in
            try tile.write(to: src.appendingPathComponent(name))
            try Data("original".utf8).write(to: dst.appendingPathComponent(name))
            try Data().write(to: backups)
            #expect(throws: (any Error).self) { try MapEngine.install(source: src, destination: dst, backups: backups) }
            #expect(try Data(contentsOf: dst.appendingPathComponent(name)) == Data("original".utf8))
        }
    }
    @Test func optionalBackupAndReplacement() throws {
        try fixture { src, dst, backups in
            try tile.write(to: src.appendingPathComponent(name))
            for marker in ["minimapmarkers.bin", "privateminimapmarkers.bin"] {
                try Data("old".utf8).write(to: dst.appendingPathComponent(marker))
            }
            let result = try MapEngine.install(source: src, destination: dst, backups: backups, preserveMarkers: false, makeBackup: false)
            #expect(result.backup == nil)
            #expect(!FileManager.default.fileExists(atPath: backups.path))
            for marker in ["minimapmarkers.bin", "privateminimapmarkers.bin"] {
                #expect(!FileManager.default.fileExists(atPath: dst.appendingPathComponent(marker).path))
            }
        }
    }
    @Test func restoreIsExactAndCreatesSafetyBackup() throws {
        try fixture { src, dst, backups in
            try tile.write(to: src.appendingPathComponent(name))
            try Data("backup marker".utf8).write(to: src.appendingPathComponent("minimapmarkers.bin"))
            try Data("current".utf8).write(to: dst.appendingPathComponent("privateminimapmarkers.bin"))
            let before = try MapEngine.snapshot(dst)
            let safety = try MapEngine.restore(backup: src, destination: dst, backups: backups)
            #expect(try MapEngine.snapshot(dst) == MapEngine.snapshot(src))
            #expect(try MapEngine.snapshot(safety!) == before)
        }
    }
    @Test func failedRestoreKeepsCurrentAndNoBackupOptionWorks() throws {
        try fixture { src, dst, backups in
            try tile.write(to: src.appendingPathComponent(name))
            try Data("current".utf8).write(to: dst.appendingPathComponent("minimapmarkers.bin"))
            let before = try MapEngine.snapshot(dst)
            #expect(throws: MapFailure.self) {
                try MapEngine.restore(backup: src, destination: dst, makeBackup: false, backups: backups) { throw MapFailure("Tibia aberto") }
            }
            #expect(try MapEngine.snapshot(dst) == before)
            #expect(!FileManager.default.fileExists(atPath: backups.path))
            let safety = try MapEngine.restore(backup: src, destination: dst, makeBackup: false, backups: backups)
            #expect(safety == nil)
            #expect(try MapEngine.snapshot(dst) == MapEngine.snapshot(src))
        }
    }
    @Test func readsBinaryMarkerAndRejectsTruncation() throws {
        let data = Data([10, 16, 10, 6, 8, 1, 16, 2, 24, 7, 16, 9, 26, 2, 72, 105, 32, 0])
        let result = try MarkerReader.read(data, source: "Normal")
        #expect(result.count == 1)
        #expect(result[0].x == 1 && result[0].y == 2 && result[0].z == 7)
        #expect(result[0].icon == 9 && result[0].text == "Hi")
        #expect(throws: MapFailure.self) { try MarkerReader.read(data.dropLast(), source: "Normal") }
        #expect(try MarkerReader.read(Data(), source: "Normal").isEmpty)
    }
    @Test func actualDownloadedPackagesPreserveRealMarkers() throws {
        // Optional integration fixtures prepared by Scripts/prepare-integration.sh.
        let root = ProcessInfo.processInfo.environment["TIBIAMAPA_INTEGRATION"]
        guard let root else { return }
        for name in ["minimapmarkers.bin", "privateminimapmarkers.bin"] {
            let data = try Data(contentsOf: URL(fileURLWithPath: root).appendingPathComponent(name))
            #expect(try MarkerReader.read(data, source: name).count > 0)
        }
        for style in MapStyle.allCases {
            try fixture { _, dst, backups in
                let input = URL(fileURLWithPath: root)
                for marker in ["minimapmarkers.bin", "privateminimapmarkers.bin"] {
                    try FileManager.default.copyItem(at: input.appendingPathComponent(marker), to: dst.appendingPathComponent(marker))
                }
                let extracted = dst.deletingLastPathComponent().appendingPathComponent("extracted")
                try MapEngine.extract(input.appendingPathComponent("\(style.rawValue).zip"), to: extracted)
                let mapTiles = try MapEngine.regularFiles(extracted.appendingPathComponent("minimap")).filter { $0.lastPathComponent.hasPrefix("Minimap_Color_") }
                let image = MapTileImage.load(try #require(mapTiles.first))
                #expect(image?.size.width == 256 && image?.size.height == 256)
                let result = try MapEngine.install(source: extracted.appendingPathComponent("minimap"), destination: dst, backups: backups)
                #expect(result.updated > 1000)
                for marker in ["minimapmarkers.bin", "privateminimapmarkers.bin"] {
                    #expect(FileManager.default.contentsEqual(atPath: input.appendingPathComponent(marker).path, andPath: dst.appendingPathComponent(marker).path))
                }
            }
        }
    }
    @Test func languageSelectionAndFallbacks() {
        #expect(AppLanguage.resolve("system", preferred: ["pl-PL", "en-US"]) == .pl)
        #expect(AppLanguage.resolve("system", preferred: ["pt-PT"]) == .ptBR)
        #expect(AppLanguage.resolve("en", preferred: ["pt-BR"]) == .en)
        #expect(AppLanguage.resolve("system", preferred: ["fr-FR", "pl"]) == .pl)
        #expect(AppLanguage.resolve("invalid", preferred: ["ja"]) == .en)
    }
    @Test func translationsAreCompleteAndKeepFormatArguments() throws {
        #expect(L.translations.count > 90)
        let format = try NSRegularExpression(pattern: "%[d@]")
        func tokens(_ value: String) -> [String] {
            format.matches(in: value, range: NSRange(value.startIndex..., in: value)).map { (value as NSString).substring(with: $0.range) }
        }
        for (key, translations) in L.translations {
            #expect(translations.count == 2)
            for translation in translations {
                #expect(!translation.isEmpty)
                #expect(tokens(key) == tokens(translation))
            }
            #expect(L.text(key, language: .ptBR) == key)
            #expect(L.text(key, language: .en) == translations[0])
            #expect(L.text(key, language: .pl) == translations[1])
        }
    }
    @Test func parsesLocalMapCoordinates() {
        #expect(TileCoordinate.parse("Minimap_Color_32256_32000_7.png") == TileCoordinate(x: 32256, y: 32000, z: 7))
        #expect(TileCoordinate.parse("privateMinimap_Color_32256_32000_7.png") != nil)
        #expect(TileCoordinate.parse("Minimap_Color_32257_32000_7.png") == nil)
        #expect(TileCoordinate.parse("Minimap_Color_32256_32000_16.png") == nil)
        #expect(TileCoordinate.parse("Minimap_WaypointCost_32256_32000_7.png") == nil)
    }
    @Test @MainActor func markerNavigationSelectsExactFloorAndCoordinates() {
        let suite = "test.navigation.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let map = MapNavigation(defaults: defaults)
        map.focus(MapMarker(id: 1, x: 32853, y: 32669, z: 12, icon: 9, text: "Test", source: "Normal"))
        #expect(map.x == 32853 && map.y == 32669 && map.floor == 12)
        #expect(map.target?.id == 1 && map.zoom == 4)
        map.move(x: -10, y: 70000)
        #expect(map.x == 0 && map.y == 65535)
        map.zoom(to: 100)
        #expect(map.zoom == 16)
        map.zoom(to: 0)
        #expect(map.zoom == 0.5)
        let restored = MapNavigation(defaults: defaults)
        #expect(restored.x == 0 && restored.y == 65535 && restored.floor == 12 && restored.zoom == 0.5)
    }

    @Test @MainActor func nativeMenusCanSwitchBetweenAllLanguages() {
        for names in NativeMenus.titles {
            for original in names {
                #expect(NativeMenus.translated(original, language: .en) == names[0])
                #expect(NativeMenus.translated(original, language: .ptBR) == names[1])
                #expect(NativeMenus.translated(original, language: .pl) == names[2])
            }
        }
    }

    @Test func scrollingRespectsSystemAndManualDirection() {
        for inverted in [false, true] {
            #expect(MapZoomPolicy.factor(delta: 10, invertedFromDevice: inverted, followsSystem: true, natural: false, precise: true) > 1)
            #expect(MapZoomPolicy.factor(delta: -10, invertedFromDevice: inverted, followsSystem: true, natural: true, precise: true) < 1)
            for natural in [false, true] {
                let eventDelta = inverted ? -10.0 : 10.0
                let factor = MapZoomPolicy.factor(delta: eventDelta, invertedFromDevice: inverted, followsSystem: false, natural: natural, precise: false)
                #expect(natural ? factor < 1 : factor > 1)
            }
        }
        #expect(MapZoomPolicy.factor(delta: 0, invertedFromDevice: false, followsSystem: true, natural: true, precise: true) == 1)
        #expect(MapZoomPolicy.factor(delta: .nan, invertedFromDevice: false, followsSystem: true, natural: true, precise: true) == 1)
    }

    @Test func overlayDeduplicatesAndFiltersByFloorAndViewport() {
        let markers = [
            MapMarker(id: 1, x: 100, y: 100, z: 7, icon: 1, text: "Home", source: "Normal"),
            MapMarker(id: 2, x: 100, y: 100, z: 7, icon: 1, text: "Home", source: "Privada"),
            MapMarker(id: 3, x: 100, y: 100, z: 7, icon: 1, text: "Different", source: "Normal"),
            MapMarker(id: 4, x: 100, y: 100, z: 8, icon: 1, text: "Above", source: "Normal"),
            MapMarker(id: 5, x: 65536, y: 100, z: 7, icon: 1, text: "Invalid", source: "Normal")
        ]
        let overlay = MarkerOverlay(markers: markers)
        #expect(overlay.count == 3)
        #expect(overlay.count(for: .normal) == 3)
        #expect(overlay.count(for: .privateMarkers) == 1)
        #expect(overlay.count(for: .none) == 0)
        #expect(overlay.visible(in: CGRect(x: 90, y: 90, width: 20, height: 20), floor: 7).count == 2)
        #expect(overlay.visible(in: CGRect(x: 90, y: 90, width: 20, height: 20), floor: 7, mode: .privateMarkers).map(\.source) == ["Privada"])
        #expect(overlay.visible(in: CGRect(x: 90, y: 90, width: 20, height: 20), floor: 7, mode: .none).isEmpty)
        #expect(overlay.visible(in: CGRect(x: 90, y: 90, width: 20, height: 20), floor: 8).count == 1)
        #expect(overlay.visible(in: CGRect(x: 200, y: 200, width: 20, height: 20), floor: 7).isEmpty)
    }

    @Test @MainActor func markerBrowserCombinesSearchSourceAndNumericSort() {
        let browser = MarkerBrowserState()
        let markers = [
            MapMarker(id: 0, x: 100, y: 1, z: 7, icon: 1, text: "Warzone", source: "Normal"),
            MapMarker(id: 1, x: 20, y: 2, z: 8, icon: 2, text: "Warzone", source: "Privada"),
            MapMarker(id: 2, x: 3, y: 3, z: 9, icon: 3, text: "Other", source: "Privada")
        ]
        browser.search = "warzone"
        #expect(browser.results(from: markers).map(\.x) == [20, 100])
        browser.origin = .privateMarkers
        #expect(browser.results(from: markers).map(\.id) == [1])
        browser.xFilter = "100"
        #expect(browser.results(from: markers).isEmpty)
        browser.origin = .all
        #expect(browser.results(from: markers).map(\.id) == [0])
        browser.resetFilters()
        #expect(browser.results(from: markers).map(\.x) == [3, 20, 100])
        browser.sortOrder = [KeyPathComparator(\.x, order: .reverse)]
        #expect(browser.results(from: markers).map(\.x) == [100, 20, 3])
        browser.iconFilter = 2
        #expect(browser.results(from: markers).map(\.id) == [1])
        browser.floorFilter = 9
        #expect(browser.results(from: markers).isEmpty)
        browser.floorFilter = 8
        #expect(browser.results(from: markers).map(\.id) == [1])
        browser.resetFilters()
        #expect(browser.iconFilter == nil && browser.floorFilter == nil)
        #expect(browser.results(from: markers).count == 3)
    }

    @Test @MainActor func allTibiaMarkerIconsLoadInCorrectOrder() {
        #expect(MarkerIcon.slots.count == 20)
        #expect(Set(MarkerIcon.slots).count == 20)
        #expect(MarkerIcon.slots[8] == 12) // sword
        #expect(MarkerIcon.slots[12] == 16) // skull
        for id in 0..<20 {
            #expect(MarkerIcon.image(for: UInt64(id))?.size == NSSize(width: 11, height: 11))
        }
        #expect(MarkerIcon.image(for: UInt64.max) != nil)
    }

    @Test func mapPackagesAreLocalizedWithoutChangingDownloadIdentifiers() {
        #expect(MapStyle.classicMarkers.title(language: .ptBR) == "Minimapa com marcações")
        #expect(MapStyle.classicMarkers.title(language: .en) == "Minimap with markers")
        #expect(MapStyle.classicMarkers.title(language: .pl) == "Minimapa ze znacznikami")
        for style in MapStyle.allCases {
            #expect(style.title(language: .ptBR) != style.title(language: .en))
            #expect(style.title(language: .pl) != style.title(language: .en))
        }
        #expect(MapStyle.gridPOI.rawValue == "minimap-with-grid-overlay-and-poi-markers")
    }
    @Test @MainActor func nativeMenuKeepsOnlyAppVisibleAndPreservesShortcuts() {
        let menu = NSMenu()
        for name in ["TibiaMapa", "Editar", "Widok", "Window", "Help"] {
            menu.addItem(NSMenuItem(title: name, action: nil, keyEquivalent: ""))
        }
        NativeMenus.simplify(menu)
        #expect(menu.items.filter { !$0.isHidden }.map(\.title) == ["TibiaMapa"])
        #expect(menu.items.dropFirst().allSatisfy { $0.allowsKeyEquivalentWhenHidden })
    }
    @Test @MainActor func authorizedParentPersistsAndMinimapAloneIsRejected() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let parent = base.appendingPathComponent("Resources")
        let destination = parent.appendingPathComponent("minimap")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let suite = "test.folder.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let installer = MapInstaller(defaults: defaults)
        #expect(!installer.hasFolderAccess)
        #expect(throws: MapFailure.self) { try installer.selectFolder(destination) }
        #expect(!installer.hasFolderAccess)
        try installer.selectFolder(parent)
        #expect(installer.destination.standardizedFileURL.path == destination.standardizedFileURL.path && installer.hasFolderAccess)
        let restored = MapInstaller(defaults: defaults)
        #expect(restored.destination.resolvingSymlinksInPath().path == destination.resolvingSymlinksInPath().path && restored.hasFolderAccess)
        defaults.set(Data([0, 1, 2]), forKey: FolderAccess.bookmarkKey)
        let invalid = MapInstaller(defaults: defaults)
        #expect(!invalid.hasFolderAccess && invalid.accessError != nil)
    }

    @Test @MainActor func detectsOnlyOfficialTibiaProcesses() {
        #expect(TibiaProcessMonitor.isTibia(bundleIdentifier: "com.tibia.client"))
        #expect(TibiaProcessMonitor.isTibia(bundleIdentifier: "com.tibia.launcher"))
        for id in [nil, "barbato.TibiaMapa", "barbato.TibiaMapaTests", "io.tibiamaps.viewer", "com.other.Tibia"] {
            #expect(!TibiaProcessMonitor.isTibia(bundleIdentifier: id))
        }
    }

    @Test func floorLabelsAreRelativeToSurface() {
        let expected = ["+7", "+6", "+5", "+4", "+3", "+2", "+1", "0", "-1", "-2", "-3", "-4", "-5", "-6", "-7", "-8"]
        #expect((0...15).map { MapFloor.label(for: $0) } == expected)
    }

}
