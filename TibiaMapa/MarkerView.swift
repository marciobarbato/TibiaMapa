import SwiftUI

@MainActor
final class MarkerBrowserState: ObservableObject {
    @Published var search = ""
    @Published var origin = MarkerDisplayMode.all
    @Published var descriptionFilter = ""
    @Published var xFilter = ""
    @Published var yFilter = ""
    @Published var floorFilter: UInt64?
    @Published var iconFilter: UInt64?
    @Published var selection: Set<Int> = []
    @Published var sortOrder: [KeyPathComparator<MapMarker>] = [KeyPathComparator(\.x)]

    var hasColumnFilters: Bool {
        !descriptionFilter.isEmpty || !xFilter.isEmpty || !yFilter.isEmpty ||
        floorFilter != nil || iconFilter != nil
    }
    func resetFilters() {
        search = ""; origin = .all
        descriptionFilter = ""; xFilter = ""; yFilter = ""
        floorFilter = nil; iconFilter = nil
    }
    func results(from markers: [MapMarker]) -> [MapMarker] {
        markers.filter { marker in
            origin.includes(marker) &&
            (search.isEmpty || "\(marker.text) \(marker.x) \(marker.y) \(MapFloor.label(for: Int(marker.z))) \(L.text(marker.source))".localizedCaseInsensitiveContains(search)) &&
            (descriptionFilter.isEmpty || marker.text.localizedCaseInsensitiveContains(descriptionFilter)) &&
            (xFilter.isEmpty || String(marker.x).contains(xFilter)) &&
            (yFilter.isEmpty || String(marker.y).contains(yFilter)) &&
            (floorFilter == nil || marker.z == floorFilter) &&
            (iconFilter == nil || marker.icon == iconFilter)
        }.sorted(using: sortOrder)
    }
}

struct MarkerView: View {
    let destination: URL
    let onOpenMap: (MapMarker) -> Void
    @ObservedObject var browser: MarkerBrowserState
    @AppStorage("appLanguage") private var language = "system"
    @State private var markers: [MapMarker] = []
    @State private var error: String?
    @State private var loading = true
    @State private var filtersOpen = false

    var body: some View {
        let _ = language
        let filtered = browser.results(from: markers)
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L.text("Suas marcações")).font(.largeTitle.bold())
                    Text(L.text("Somente leitura · dê dois cliques para ir até a marcação")).foregroundStyle(.secondary)
                }
                Spacer()
                Button(L.text("Abrir no mapa")) { open(browser.selection) }
                    .disabled(browser.selection.count != 1).buttonStyle(.borderedProminent)
            }
            HStack {
                TextField(L.text("Buscar descrição, coordenada ou origem"), text: $browser.search)
                    .textFieldStyle(.roundedBorder)
                Picker(L.text("Origem"), selection: $browser.origin) {
                    ForEach([MarkerDisplayMode.all, .normal, .privateMarkers]) { mode in
                        Text(mode.title).tag(mode)
                    }
                }.frame(width: 210)
                Button {
                    filtersOpen.toggle()
                } label: {
                    Label(L.text("Filtros de coluna"), systemImage: browser.hasColumnFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }.popover(isPresented: $filtersOpen) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L.text("Filtros de coluna")).font(.headline)
                        TextField(L.text("Descrição"), text: $browser.descriptionFilter)
                        TextField("X", text: $browser.xFilter)
                        TextField("Y", text: $browser.yFilter)
                        Picker(L.text("Andar"), selection: $browser.floorFilter) {
                            Text(L.text("Todos os andares")).tag(nil as UInt64?)
                            ForEach(Array(Set(markers.map(\.z))).sorted(), id: \.self) { floor in
                                Text(MapFloor.label(for: Int(floor))).tag(Optional(floor))
                            }
                        }.pickerStyle(.menu)
                        Picker(L.text("Ícone"), selection: $browser.iconFilter) {
                            Text(L.text("Todos os ícones")).tag(nil as UInt64?)
                            ForEach(Array(Set(markers.map(\.icon))).sorted(), id: \.self) { icon in
                                HStack {
                                    MarkerIconView(id: icon)
                                    Text(L.text("Ícone") + " \(icon)")
                                }.tag(Optional(icon))
                            }
                        }.pickerStyle(.menu)
                        Button(L.text("Limpar filtros")) { browser.resetFilters() }
                    }.textFieldStyle(.roundedBorder).padding(18).frame(width: 260)
                }
            }
            if loading { ProgressView(L.text("Lendo arquivos…")) }
            if let error { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
            Table(filtered, selection: $browser.selection, sortOrder: $browser.sortOrder) {
                TableColumn(L.text("Descrição"), value: \.text).width(min: 160)
                TableColumn("X", value: \.x) { Text(String($0.x)) }.width(60)
                TableColumn("Y", value: \.y) { Text(String($0.y)) }.width(60)
                TableColumn(L.text("Andar"), value: \.z) { Text(MapFloor.label(for: Int($0.z))) }.width(55)
                TableColumn(L.text("Ícone"), value: \.icon) { MarkerIconView(id: $0.icon) }.width(45)
                TableColumn(L.text("Origem"), value: \.sourceTitle) { Text($0.sourceTitle) }.width(95)
            }
            .contextMenu(forSelectionType: Int.self) { ids in
                Button(L.text("Abrir no mapa")) { open(ids) }.disabled(ids.count != 1)
            } primaryAction: { ids in open(ids) }
            Text(L.format("%d de %d marcações. Andar 0 = superfície.", filtered.count, markers.count))
                .font(.caption).foregroundStyle(.secondary)
            Text(L.text("As bases normal e privada podem conter marcações repetidas. Nenhum arquivo é alterado."))
                .font(.caption).foregroundStyle(.secondary)
        }.padding(28)
        .task(id: destination) {
            loading = true
            let folder = destination
            let result = await Task.detached { MarkerReader.load(folder: folder) }.value
            guard !Task.isCancelled else { return }
            markers = result.0
            error = result.1
            loading = false
        }
    }
    private func open(_ ids: Set<Int>) {
        guard ids.count == 1, let id = ids.first, let marker = markers.first(where: { $0.id == id }) else { return }
        onOpenMap(marker)
    }
}
