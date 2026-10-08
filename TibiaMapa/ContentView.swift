import SwiftUI
import AppKit

enum AppPage: String, CaseIterable, Identifiable {
    case update = "Seus mapas", map = "Explorar mapa", markers = "Suas marcações", backups = "Backups", settings = "Configurações", credits = "Créditos"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .update: return "square.and.arrow.down"
        case .map: return "map"
        case .markers: return "mappin.and.ellipse"
        case .backups: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        case .credits: return "info.circle"
        }
    }
}

struct ContentView: View {
    @StateObject private var installer = MapInstaller()
    @StateObject private var navigation = MapNavigation()
    @StateObject private var client = TibiaProcessMonitor()
    @StateObject private var markerBrowser = MarkerBrowserState()
    @AppStorage("appLanguage") private var language = "system"
    @State private var page: AppPage? = .update
    @AppStorage(MapPreferenceKeys.style) private var style: MapStyle = .classicMarkers
    @AppStorage(MapPreferenceKeys.preserveMarkers) private var preserveMarkers = true
    @AppStorage(MapPreferenceKeys.makeBackup) private var makeBackup = true
    @State private var confirm = false
    @State private var restoreBackup: URL?
    @State private var confirmRestore = false
    @State private var backups: [BackupEntry] = []
    @State private var selectionError: String?
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 10) {
                    Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 34, height: 34)
                    Text("TibiaMapa").font(.title3.bold())
                }.padding(.horizontal, 16).padding(.top, 22)
                List(AppPage.allCases, selection: $page) { item in
                    Label(L.text(item.rawValue), systemImage: item.symbol).tag(item)
                }.listStyle(.sidebar).id(language)
                VStack(alignment: .leading, spacing: 10) {
                    Text("🇧🇷 Proudly made in Brasil").font(.caption2).foregroundStyle(.secondary)
                    Text("Marcio Barbato · 2.3").font(.caption2).foregroundStyle(.tertiary)
                }.padding(18)
            }.navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            Group {
                switch page ?? .update {
                case .map:
                    if installer.hasFolderAccess { MapViewer(destination: installer.destination, navigation: navigation) }
                    else { accessPage }
                case .markers:
                    if installer.hasFolderAccess {
                        MarkerView(destination: installer.destination, onOpenMap: { marker in
                            navigation.focus(marker)
                            page = .map
                        }, browser: markerBrowser)
                    } else { accessPage }
                default:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            Text(L.text((page ?? .update).rawValue)).font(.largeTitle.bold())
                            switch page ?? .update {
                            case .update: updatePage
                            case .backups: backupPage
                            case .settings: settingsPage
                            case .credits: creditsPage
                            default: EmptyView()
                            }
                        }.padding(32).frame(maxWidth: 920, alignment: .leading)
                    }
                }
            }.background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 1000, minHeight: 680)
        .tint(.teal)
        .onAppear { NativeMenus.install() }
        .onChange(of: language) { _ in NativeMenus.update() }
        .environment(\.locale, Locale(identifier: AppLanguage.resolve(language, preferred: Locale.preferredLanguages).rawValue))
        .confirmationDialog(L.text("Atualizar os mapas?"), isPresented: $confirm, titleVisibility: .visible) {
            Button(L.text("Atualizar mapas"), role: preserveMarkers ? nil : .destructive) {
                Task { await installer.install(style: style, preserveMarkers: preserveMarkers, makeBackup: makeBackup) }
            }
            Button(L.text("Cancelar"), role: .cancel) {}
        } message: {
            Text(L.format("Destino: %@", installer.destination.path) + "\n\n" + L.text(preserveMarkers ? "Suas marcações serão mantidas. " : "Suas marcações atuais serão removidas e substituídas pelas do pacote, quando houver. ") + L.text(makeBackup ? "Um backup completo será criado." : "Backup desativado: não será possível desfazer esta operação pelo aplicativo."))
        }
        .confirmationDialog(L.text("Restaurar este backup?"), isPresented: $confirmRestore, titleVisibility: .visible) {
            Button(L.text("Restaurar mapas e marcações"), role: .destructive) {
                if let backup = restoreBackup { Task { await installer.restore(backup: backup, makeBackup: makeBackup) } }
            }
            Button(L.text("Cancelar"), role: .cancel) {}
        } message: {
            Text(L.format("Destino: %@", installer.destination.path) + "\n\n" + L.format("Todos os mapas e marcações atuais serão substituídos pelo backup selecionado: %@. ", restoreBackup?.lastPathComponent ?? "") + L.text(makeBackup ? "O estado atual será salvo em outro backup." : "Sem backup do estado atual. Esta troca não poderá ser desfeita pelo app."))
        }
        .alert(L.text("Pasta inválida"), isPresented: Binding(get: { selectionError != nil }, set: { if !$0 { selectionError = nil } })) {
            Button("OK") { selectionError = nil }
        } message: { Text(selectionError ?? "") }
    }
    private var updatePage: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(L.text("Explore mais. Mantenha suas marcações.")).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 18) {
                Label(L.text("Estilo do mapa"), systemImage: "map.fill").font(.headline)
                Picker(L.text("Estilo do mapa"), selection: $style) {
                    ForEach(MapStyle.allCases) { Text($0.title).tag($0) }
                }.id(language).labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                Divider()
                Toggle(L.text("Preservar minhas marcações"), isOn: $preserveMarkers)
                Toggle(L.text("Fazer backup antes de alterar os mapas"), isOn: $makeBackup)
                Text(L.text(preserveMarkers ? "Suas marcações pessoais são mantidas. As marcações que o TibiaMapa importou são trocadas pelas do pacote escolhido; marcações editadas são preservadas." : "As marcações atuais, inclusive privadas, serão substituídas pelas do pacote. Um mapa sem marcadores deixará você sem marcações."))
                    .font(.callout).foregroundStyle(preserveMarkers ? Color.secondary : Color.orange)
            }.panel().disabled(installer.isBusy)
            destinationCard
            if !installer.hasFolderAccess {
                VStack(alignment: .leading, spacing: 12) {
                    Label(L.text("Permita o acesso para atualizar seus mapas"), systemImage: "folder.badge.plus")
                        .font(.headline)
                    Text(L.text("Para baixar e instalar os mapas, escolha a pasta Resources do Tibia, que contém minimap."))
                        .foregroundStyle(.secondary)
                    Button(L.text("Escolher pasta Resources…")) {
                        chooseFolder(at: MapEngine.defaultDestination.deletingLastPathComponent())
                    }.buttonStyle(.borderedProminent).controlSize(.large)
                }.panel()
            }
            HStack {
                clientStatus
                Spacer()
                Button(L.text("Atualizar mapas…")) { client.refresh(); if !client.isRunning { confirm = true } }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(installer.isBusy || !installer.hasFolderAccess || client.isRunning)
            }
            if installer.isBusy || installer.failed || !installer.status.isEmpty || !installer.hasFolderAccess {
                statusCard
            }
        }
    }
    private var clientStatus: some View {
        Label(client.isRunning ? L.format("Em execução: %@. Feche para continuar.", client.description) : L.text("Tibia e launcher fechados."),
              systemImage: client.isRunning ? "exclamationmark.circle" : "checkmark.circle")
            .font(.callout).foregroundStyle(client.isRunning ? Color.orange : Color.secondary)
    }
    private var destinationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L.text("Pasta do minimapa"), systemImage: "folder").font(.headline)
                Spacer()
                Button(L.text("Escolher…"), action: { chooseFolder() }).disabled(installer.isBusy)
                Button(L.text("Padrão")) { chooseFolder(at: MapEngine.defaultDestination.deletingLastPathComponent()) }.disabled(installer.isBusy)
            }
            if !installer.hasFolderAccess {
                Text(L.text("Escolha Resources, a pasta que contém minimap, para habilitar a atualização."))
                    .foregroundStyle(.orange)
            }
            if let error = installer.accessError { Text(error).font(.caption).foregroundStyle(.orange) }
            Text(installer.destination.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).id(installer.destination)
        }.panel()
    }
    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if installer.isBusy { ProgressView().controlSize(.small) }
                else { Image(systemName: installer.failed ? "exclamationmark.triangle.fill" : installer.hasFolderAccess ? "checkmark.circle" : "folder.badge.questionmark").foregroundStyle(installer.failed || !installer.hasFolderAccess ? .orange : .teal) }
                Text(L.text(installer.hasFolderAccess ? installer.status : "Aguardando acesso à pasta Resources")).font(.headline)
            }
            if !installer.log.isEmpty { Text(installer.log).font(.caption.monospaced()).textSelection(.enabled) }
        }.panel()
    }
    private var backupPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(L.text("Restaure mapas e marcações a partir de uma cópia anterior.")).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 16) {
                Label(L.text("Backups"), systemImage: "externaldrive.badge.timemachine").font(.headline)
                Text(L.text("A restauração substitui todo o conteúdo da pasta do minimapa. A preservação de marcações não se aplica à restauração.")).foregroundStyle(.secondary)
                Toggle(L.text("Fazer backup antes de alterar os mapas"), isOn: $makeBackup)
                HStack {
                    Button(L.text("Atualizar lista"), action: reloadBackups)
                    Button(L.text("Abrir backups"), action: openBackups)
                    Button(L.text("Escolher outra pasta…"), action: chooseBackup).disabled(!installer.hasFolderAccess || client.isRunning)
                }
                if backups.isEmpty {
                    Text(L.text("Nenhum backup encontrado nesta instalação.")).foregroundStyle(.secondary)
                } else {
                    ForEach(backups) { backup in
                        HStack(spacing: 16) {
                            Image(systemName: "folder.fill").foregroundStyle(.teal)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(backup.date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened)
                                    .locale(Locale(identifier: L.language.rawValue)))).font(.headline)
                                if backup.isPreRestore {
                                    Text(L.text("Cópia anterior a uma restauração")).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button(L.text("Restaurar")) {
                                restoreBackup = backup.url
                                confirmRestore = true
                            }.disabled(!installer.hasFolderAccess || client.isRunning)
                        }.padding(.vertical, 4)
                        if backup.id != backups.last?.id { Divider() }
                    }
                }
                Text(MapEngine.backupRoot.path).font(.caption2).foregroundStyle(.tertiary).textSelection(.enabled)
            }.panel().disabled(installer.isBusy)
            destinationCard
            clientStatus
            statusCard
        }.onAppear(perform: reloadBackups)
            .onChange(of: installer.isBusy) { busy in if !busy { reloadBackups() } }
    }
    private var settingsPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 16) {
                Label(L.text("Idioma"), systemImage: "globe").font(.headline)
                Picker(L.text("Idioma"), selection: $language) {
                    ForEach(AppLanguage.allCases) { Text($0.title).tag($0.rawValue) }
                }.id(language).frame(maxWidth: 430)
                Text(L.text("A opção automática segue os idiomas preferidos do macOS. A escolha manual é salva neste Mac.")).font(.callout).foregroundStyle(.secondary)
            }.panel()
            destinationCard
        }
    }
    private var creditsPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 20) {
                Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 84, height: 84)
                VStack(alignment: .leading, spacing: 7) {
                    Text("TibiaMapa").font(.title.bold())
                    Text("2.3 · macOS").foregroundStyle(.secondary)
                    Text("🇧🇷 Proudly made in Brasil").font(.callout)
                }
            }.panel()
            VStack(alignment: .leading, spacing: 18) {
                credit("Tibia", "Tibia pertence à CipSoft GmbH.", "https://www.tibia.com")
                Divider()
                credit("TibiaMaps.io", "Os mapas pertencem ao TibiaMaps.io.", "https://tibiamaps.io")
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Marcio Barbato").font(.headline)
                    Text(L.text("Programa desenvolvido por Marcio Barbato.")).foregroundStyle(.secondary)
                }
            }.panel()
            Link("TibiaMaps.io · Mathias Bynens · MIT License", destination: URL(string: "https://github.com/tibiamaps/tibia-map-data/blob/main/LICENSE-MIT.txt")!).font(.caption)
            Link("ZIPFoundation · Thomas Zoechling · MIT License", destination: URL(string: "https://github.com/weichsel/ZIPFoundation")!).font(.caption)
            Text(L.text("Aplicativo independente, sem afiliação com TibiaMaps.io ou CipSoft.")).font(.caption).foregroundStyle(.secondary)
        }
    }
    private func credit(_ title: String, _ detail: String, _ url: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Link(title, destination: URL(string: url)!).font(.headline)
            Text(L.text(detail)).foregroundStyle(.secondary)
        }
    }
    private func openBackups() {
        do {
            try FileManager.default.createDirectory(at: MapEngine.backupRoot, withIntermediateDirectories: true)
            NSWorkspace.shared.open(MapEngine.backupRoot)
        } catch { selectionError = error.localizedDescription }
    }
    private func reloadBackups() {
        do { backups = try BackupCatalog.list() }
        catch { selectionError = error.localizedDescription }
    }
    private func chooseBackup() {
        let panel = NSOpenPanel()
        panel.title = L.text("Selecione a pasta do backup para restaurar")
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.directoryURL = MapEngine.backupRoot
        guard panel.runModal() == .OK, let url = panel.url else { return }
        restoreBackup = url; confirmRestore = true
    }
    private var accessPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(L.text("Conecte seus mapas")).font(.largeTitle.bold())
            Text(L.text("Escolha a pasta Resources do Tibia, que contém minimap. O macOS lembrará sua autorização para visualizar, atualizar e restaurar os mapas.")).foregroundStyle(.secondary)
            destinationCard
        }.padding(32).frame(maxWidth: 850)
    }
    private func chooseFolder(at suggested: URL? = nil) {
        let panel = NSOpenPanel()
        panel.title = L.text("Autorizar pasta dos mapas")
        panel.message = L.text("Selecione a pasta que contém minimap, como Resources, para permitir a atualização segura.")
        panel.prompt = L.text("Autorizar pasta")
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        panel.directoryURL = suggested ?? installer.destination.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try installer.selectFolder(url) }
        catch { selectionError = error.localizedDescription }
    }

}
extension View {
    func panel() -> some View {
        self.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.055)))
    }
}
