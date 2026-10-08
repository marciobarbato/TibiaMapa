import Foundation
import Darwin
import CryptoKit
import ZIPFoundation

struct MapFailure: LocalizedError {
    let message: String
    var errorDescription: String? { L.text(message) }
    init(_ message: String) { self.message = message }
}

/// Updates map tiles; marker preservation and backups are enabled by default.
enum MapEngine {
    static let fm = FileManager.default
    static let markerManifestName = ".tibiamapa-managed-markers.json"
    static var defaultDestination: URL {
        // Suggested location for the system folder picker; never an access grant.
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/CipSoft GmbH/Tibia/packages/Tibia.app/Contents/Resources/minimap")
    }
    static var backupRoot: URL {
        fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TibiaMapa/Backups")
    }
    static func destination(_ chosen: URL) throws -> URL {
        let url = chosen.standardizedFileURL
        switch url.lastPathComponent.lowercased() {
        case "minimap": return url
        case "resources": return url.appendingPathComponent("minimap")
        case "tibia.app", "tibiaexternal.app": return url.appendingPathComponent("Contents/Resources/minimap")
        case "packages": return url.appendingPathComponent("Tibia.app/Contents/Resources/minimap")
        default: throw MapFailure("Selecione a pasta minimap, Resources, packages ou o aplicativo Tibia.")
        }
    }
    static func regularFiles(_ directory: URL) throws -> [URL] {
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw MapFailure(L.format("A pasta não pode ser um link simbólico: %@", directory.path))
        }
        let files = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        for file in files {
            let info = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard info.isRegularFile == true, info.isSymbolicLink != true else {
                throw MapFailure(L.format("Arquivo ou subpasta inesperada: %@. Nada foi alterado.", file.lastPathComponent))
            }
        }
        return files
    }
    static func isTile(_ name: String) -> Bool {
        name.range(of: #"^Minimap_(Color|WaypointCost)_[0-9]+_[0-9]+_([0-9]|1[0-5])\.png$"#, options: .regularExpression) != nil
    }
    static func extract(_ zip: URL, to folder: URL) throws {
        let archive = try Archive(url: zip, accessMode: .read)
        var size: UInt64 = 0
        var count = 0
        for entry in archive {
            count += 1
            size += UInt64(entry.uncompressedSize)
            let parts = entry.path.split(separator: "/", omittingEmptySubsequences: false)
            guard !entry.path.hasPrefix("/"), !parts.contains(".."), !entry.path.contains("\\"),
                  entry.type != .symlink, size < 512 * 1024 * 1024, count < 30000 else {
                throw MapFailure("O pacote de mapas contém entradas inválidas ou excede o limite de tamanho.")
            }
        }
        try fm.unzipItem(at: zip, to: folder)
    }
    struct Result {
        let updated: Int
        let preserved: Int
        let backup: URL?
    }
    static func install(source: URL, destination: URL, backups: URL = backupRoot, preserveMarkers: Bool = true, makeBackup: Bool = true,
                        beforeCommit: () throws -> Void = {}) throws -> Result {
        let tiles = try regularFiles(source).filter { isTile($0.lastPathComponent) }
        guard !tiles.isEmpty else { throw MapFailure("O pacote não contém mapas válidos.") }
        for tile in tiles {
            let data = try Data(contentsOf: tile)
            guard data.count >= 24, data.prefix(8) == Data([137,80,78,71,13,10,26,10]),
                  Array(data[16..<24]) == [0,0,1,0,0,0,1,0] else {
                throw MapFailure(L.format("Mapa inválido: %@", tile.lastPathComponent))
            }
        }
        let original = try regularFiles(destination)
        let fingerprints = try snapshot(destination)
        let id = UUID().uuidString
        let backup = backups.appendingPathComponent("\(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-"))-\(id)")
        if makeBackup {
            try fm.createDirectory(at: backups, withIntermediateDirectories: true)
            try fm.copyItem(at: destination, to: backup)
        }
        let stage = destination.deletingLastPathComponent().appendingPathComponent(".tibiamapa-\(id)")
        defer { try? fm.removeItem(at: stage) }
        try fm.copyItem(at: destination, to: stage)
        for tile in tiles {
            let out = stage.appendingPathComponent(tile.lastPathComponent)
            if fm.fileExists(atPath: out.path) { try fm.removeItem(at: out) }
            try fm.copyItem(at: tile, to: out)
        }
        if !preserveMarkers {
            for name in ["minimapmarkers.bin", "privateminimapmarkers.bin"] {
                let marker = stage.appendingPathComponent(name)
                if fm.fileExists(atPath: marker.path) { try fm.removeItem(at: marker) }
            }
        }
        let incomingMarkers = source.appendingPathComponent("minimapmarkers.bin")
        let existingMarkers = stage.appendingPathComponent("minimapmarkers.bin")
        let manifestURL = stage.appendingPathComponent(markerManifestName)
        let incoming = fm.fileExists(atPath: incomingMarkers.path) ? try Data(contentsOf: incomingMarkers) : Data()
        var previous: MarkerMerger.Manifest?
        if preserveMarkers, fm.fileExists(atPath: manifestURL.path) {
            do {
                let data = try Data(contentsOf: manifestURL)
                guard data.count <= 30 * 1024 * 1024 else { throw MapFailure("Registro de marcações importadas inválido.") }
                previous = try JSONDecoder().decode(MarkerMerger.Manifest.self, from: data)
            } catch {
                throw MapFailure("Registro de marcações importadas inválido.")
            }
        }
        if preserveMarkers, (!incoming.isEmpty || previous != nil) {
            let privateMarkers = stage.appendingPathComponent("privateminimapmarkers.bin")
            let local = fm.fileExists(atPath: existingMarkers.path) ? try Data(contentsOf: existingMarkers) : Data()
            let personal = fm.fileExists(atPath: privateMarkers.path) ? try Data(contentsOf: privateMarkers) : Data()
            let result = try MarkerMerger.reconcile(existing: local, privateMarkers: personal, incoming: incoming, previous: previous)
            try result.data.write(to: existingMarkers)
            try JSONEncoder().encode(result.manifest).write(to: manifestURL)
        } else if !preserveMarkers {
            if fm.fileExists(atPath: incomingMarkers.path) {
                _ = try MarkerReader.read(incoming, source: "Normal")
                try incoming.write(to: existingMarkers)
            }
            let records = try MarkerReader.fields(incoming).filter { $0.number == 1 }.map(\.encoded)
            try JSONEncoder().encode(MarkerMerger.Manifest(records: records)).write(to: manifestURL)
        }
        // Check for concurrent client writes before the atomic directory exchange.
        guard try snapshot(destination) == fingerprints else {
            throw MapFailure("Os mapas foram alterados durante a instalação. Feche o Tibia e tente novamente.")
        }
        try beforeCommit()
        guard renamex_np(stage.path, destination.path, UInt32(RENAME_SWAP)) == 0 else {
            throw MapFailure(L.format("Não foi possível concluir a troca de mapas: %@. Os mapas originais foram mantidos.", String(cString: strerror(errno))))
        }
        let preserved = original.filter {
            let name = $0.lastPathComponent
            return !isTile(name) && name != markerManifestName && name != "minimapmarkers.bin" &&
                (preserveMarkers || name != "privateminimapmarkers.bin")
        }.count
        return Result(updated: tiles.count, preserved: preserved, backup: makeBackup ? backup : nil)
    }
    static func snapshot(_ directory: URL) throws -> [String: Data] {
        try Dictionary(uniqueKeysWithValues: regularFiles(directory).map {
            ($0.lastPathComponent, Data(SHA256.hash(data: try Data(contentsOf: $0))))
        })
    }
    static func restore(backup: URL, destination: URL, makeBackup: Bool = true,
                        backups: URL = backupRoot, beforeCommit: () throws -> Void = {}) throws -> URL? {
        let files = try regularFiles(backup)
        guard files.contains(where: { isTile($0.lastPathComponent) }) else {
            throw MapFailure("Selecione um backup que contenha arquivos de minimapa.")
        }
        guard backup.standardizedFileURL != destination.standardizedFileURL,
              !backup.path.hasPrefix(destination.path + "/") else {
            throw MapFailure("O backup precisa estar fora da pasta de destino.")
        }
        let original = try snapshot(destination)
        let source = try snapshot(backup)
        let id = UUID().uuidString
        let safety = backups.appendingPathComponent("Antes-de-restaurar-\(id)")
        if makeBackup {
            try fm.createDirectory(at: backups, withIntermediateDirectories: true)
            try fm.copyItem(at: destination, to: safety)
        }
        let stage = destination.deletingLastPathComponent().appendingPathComponent(".tibiamapa-restore-\(id)")
        defer { try? fm.removeItem(at: stage) }
        try fm.copyItem(at: backup, to: stage)
        guard try snapshot(stage) == source, try snapshot(destination) == original else {
            throw MapFailure("Os arquivos mudaram durante a restauração. Nada foi substituído.")
        }
        try beforeCommit()
        guard renamex_np(stage.path, destination.path, UInt32(RENAME_SWAP)) == 0 else {
            throw MapFailure(L.format("Não foi possível restaurar: %@. Os mapas atuais foram mantidos.", String(cString: strerror(errno))))
        }
        return makeBackup ? safety : nil
    }

}
