import SwiftUI
import AppKit

enum MapStyle: String, CaseIterable, Identifiable {
    case classicMarkers = "minimap-with-markers"
    case classic = "minimap-without-markers"
    case gridMarkers = "minimap-with-grid-overlay-and-markers"
    case gridPOI = "minimap-with-grid-overlay-and-poi-markers"
    case grid = "minimap-with-grid-overlay-without-markers"
    var id: String { rawValue }
    var title: String { title(language: L.language) }
    func title(language: AppLanguage) -> String {
        switch self {
        case .classicMarkers: return L.text("Minimapa com marcações", language: language)
        case .classic: return L.text("Minimapa sem marcações", language: language)
        case .gridMarkers: return L.text("Minimapa com grade e marcações", language: language)
        case .gridPOI: return L.text("Minimapa com grade e pontos de interesse", language: language)
        case .grid: return L.text("Minimapa com grade sem marcações", language: language)
        }
    }
}

@MainActor
final class MapInstaller: ObservableObject {
    @Published var isBusy = false
    @Published var status = "Pronto para atualizar"
    @Published var log = ""
    @Published var failed = false
    @Published var lastBackup: URL?
    private let defaults: UserDefaults
    @Published private(set) var destination = MapEngine.defaultDestination
    @Published private(set) var hasFolderAccess = false
    @Published private(set) var accessError: String?
    private var folderAccess: FolderAccess?
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        do {
            if let access = try FolderAccess.restore(from: defaults) {
                folderAccess = access
                destination = access.destination
                hasFolderAccess = true
            }
        } catch { accessError = error.localizedDescription }
    }
    func selectFolder(_ root: URL) throws {
        let access = try FolderAccess(root: root)
        try access.save(in: defaults)
        folderAccess = access
        destination = access.destination
        hasFolderAccess = true
        accessError = nil
    }
    private func requireFolderAccess() throws {
        guard hasFolderAccess, folderAccess != nil else {
            throw MapFailure("Autorize a pasta dos mapas antes de continuar.")
        }
    }

    static func requireClosedClient() throws {
        if !TibiaProcessMonitor.runningIdentifiers().isEmpty {
            throw MapFailure("Feche o Tibia e o launcher antes de atualizar os mapas.")
        }
    }
    func install(style: MapStyle, preserveMarkers: Bool, makeBackup: Bool) async {
        guard !isBusy else { return }
        isBusy = true
        failed = false
        log = ""
        defer { isBusy = false }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        do {
            try requireFolderAccess()
            try Self.requireClosedClient()
            _ = try MapEngine.regularFiles(destination)
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            status = "Baixando mapas…"
            let name = style.rawValue
            let url = URL(string: "https://tibiamaps.github.io/tibia-map-data/\(name).zip")!
            let (download, response) = try await URLSession.shared.download(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  response.url?.scheme == "https" else { throw MapFailure("O servidor não retornou um pacote válido. Tente novamente mais tarde.") }
            let zip = temp.appendingPathComponent("maps.zip")
            try FileManager.default.moveItem(at: download, to: zip)
            status = "Verificando pacote e preparando backup…"
            let target = destination
            let extracted = temp.appendingPathComponent("extracted")
            let result = try await Task.detached(priority: .userInitiated) {
                try MapEngine.extract(zip, to: extracted)
                return try MapEngine.install(source: extracted.appendingPathComponent("minimap"), destination: target, preserveMarkers: preserveMarkers, makeBackup: makeBackup) {
                    // Check process state on the main actor immediately before committing.
                    try DispatchQueue.main.sync { try MapInstaller.requireClosedClient() }
                }
            }.value
            lastBackup = result.backup
            status = preserveMarkers ? "Mapas atualizados. Suas marcações foram preservadas." : "Mapas e marcações atualizados conforme o pacote."
            log = L.format("%d arquivos de mapa instalados.\n%d arquivos pessoais preservados sem modificações.\n\nDestino: %@\n\nBackup: %@", result.updated, result.preserved, target.path, result.backup?.path ?? L.text("Desativado"))
        } catch {
            failed = true
            status = "Não foi possível atualizar"
            log = error.localizedDescription
        }
    }
    func restore(backup: URL, makeBackup: Bool) async {
        guard !isBusy else { return }
        let accessingBackup = backup.startAccessingSecurityScopedResource()
        defer { if accessingBackup { backup.stopAccessingSecurityScopedResource() } }
        isBusy = true
        failed = false
        status = "Restaurando backup…"
        log = ""
        defer { isBusy = false }
        do {
            try requireFolderAccess()
            try Self.requireClosedClient()
            let target = destination
            let safety = try await Task.detached(priority: .userInitiated) {
                try MapEngine.restore(backup: backup, destination: target, makeBackup: makeBackup) {
                    try DispatchQueue.main.sync { try MapInstaller.requireClosedClient() }
                }
            }.value
            lastBackup = safety
            status = "Backup restaurado com sucesso."
            log = L.format("Restaurado de: %@\nDestino: %@\nBackup anterior à restauração: %@", backup.path, target.path, safety?.path ?? L.text("Desativado"))
        } catch {
            failed = true
            status = "Não foi possível restaurar"
            log = error.localizedDescription
        }
    }

}
