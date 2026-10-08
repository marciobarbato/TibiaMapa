import Foundation

/// Holds the user-selected parent folder open for the lifetime of its readers.
/// The parent grant also covers staging and atomic replacement of minimap.
final class FolderAccess {
    static let bookmarkKey = "minimapParentBookmark"
    let root: URL
    let destination: URL
    private let started: Bool
    init(root: URL) throws {
        self.root = root
        started = root.startAccessingSecurityScopedResource()
        do {
            guard root.lastPathComponent.lowercased() != "minimap" else {
                throw MapFailure("Selecione a pasta que contém minimap, como Resources, para permitir a atualização segura.")
            }
            destination = try MapEngine.destination(root)
            let info = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard info.isDirectory == true, info.isSymbolicLink != true else {
                throw MapFailure("Selecione uma pasta válida, sem links simbólicos.")
            }
            _ = try MapEngine.regularFiles(destination)
        } catch {
            if started { root.stopAccessingSecurityScopedResource() }
            throw error
        }
    }
    deinit { if started { root.stopAccessingSecurityScopedResource() } }
    func save(in defaults: UserDefaults) throws {
        let data = try root.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(data, forKey: Self.bookmarkKey)
    }
    static func restore(from defaults: UserDefaults) throws -> FolderAccess? {
        guard let data = defaults.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        let root = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        let access = try FolderAccess(root: root)
        if stale { try access.save(in: defaults) }
        return access
    }
}
