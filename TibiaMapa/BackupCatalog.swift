import Foundation

struct BackupEntry: Identifiable {
    let url: URL
    let date: Date
    let isPreRestore: Bool
    var id: URL { url }
}

enum BackupCatalog {
    static func list(in root: URL = MapEngine.backupRoot) throws -> [BackupEntry] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return [] }
        let folders = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .creationDateKey])
        return folders.compactMap { folder in
            guard let values = try? folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .creationDateKey]),
                  values.isDirectory == true, values.isSymbolicLink != true,
                  let files = try? MapEngine.regularFiles(folder),
                  files.contains(where: { MapEngine.isTile($0.lastPathComponent) }) else { return nil }
            let name = folder.lastPathComponent
            return BackupEntry(url: folder, date: date(from: name) ?? values.creationDate ?? .distantPast,
                               isPreRestore: name.hasPrefix("Antes-de-restaurar-"))
        }.sorted { $0.date > $1.date }
    }

    private static func date(from name: String) -> Date? {
        let prefix = String(name.prefix(20))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        return formatter.date(from: prefix)
    }
}
