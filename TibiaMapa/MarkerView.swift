import SwiftUI

struct MarkerView: View {
    let destination: URL
    let onOpenMap: (MapMarker) -> Void
    @AppStorage("appLanguage") private var language = "system"
    @State private var markers: [MapMarker] = []
    @State private var selection: Set<Int> = []
    @State private var search = ""
    @State private var error: String?
    @State private var loading = true
    var filtered: [MapMarker] {
        guard !search.isEmpty else { return markers }
        return markers.filter { "\($0.text) \($0.x) \($0.y) \(MapFloor.label(for: Int($0.z))) \(L.text($0.source))".localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        let _ = language
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L.text("Suas marcações")).font(.largeTitle.bold())
                    Text(L.text("Somente leitura · dê dois cliques para ir até a marcação")).foregroundStyle(.secondary)
                }
                Spacer()
                Button(L.text("Abrir no mapa")) { open(selection) }
                    .disabled(selection.count != 1).buttonStyle(.borderedProminent)
            }
            TextField(L.text("Buscar descrição, coordenada ou origem"), text: $search)
                .textFieldStyle(.roundedBorder)
            if loading { ProgressView(L.text("Lendo arquivos…")) }
            if let error { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
            Table(filtered, selection: $selection) {
                TableColumn(L.text("Descrição"), value: \.text).width(min: 160)
                TableColumn("X") { Text(String($0.x)) }.width(60)
                TableColumn("Y") { Text(String($0.y)) }.width(60)
                TableColumn(L.text("Andar")) { Text(MapFloor.label(for: Int($0.z))) }.width(55)
                TableColumn(L.text("Ícone")) { MarkerIconView(id: $0.icon) }.width(45)
                TableColumn(L.text("Origem")) { Text(L.text($0.source)) }.width(75)
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
