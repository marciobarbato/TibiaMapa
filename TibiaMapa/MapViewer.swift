import SwiftUI
import AppKit
import ImageIO

struct TileCoordinate: Hashable {
    let x: Int
    let y: Int
    let z: Int
    static func parse(_ name: String) -> TileCoordinate? {
        let stem = name.replacingOccurrences(of: "privateMinimap_Color_", with: "").replacingOccurrences(of: "Minimap_Color_", with: "")
        guard stem != name, stem.hasSuffix(".png") else { return nil }
        let parts = stem.dropLast(4).split(separator: "_")
        guard parts.count == 3, let x = Int(parts[0]), let y = Int(parts[1]), let z = Int(parts[2]),
              (0...65535).contains(x), (0...65535).contains(y), (0...15).contains(z), x % 256 == 0, y % 256 == 0 else { return nil }
        return TileCoordinate(x: x, y: y, z: z)
    }
}

@MainActor
final class MapNavigation: ObservableObject {
    private let defaults: UserDefaults
    @Published var x: Double { didSet { defaults.set(x, forKey: MapPreferenceKeys.x) } }
    @Published var y: Double { didSet { defaults.set(y, forKey: MapPreferenceKeys.y) } }
    @Published var floor: Int { didSet { defaults.set(floor, forKey: MapPreferenceKeys.floor) } }
    @Published var zoom: Double { didSet { defaults.set(zoom, forKey: MapPreferenceKeys.zoom) } }
    @Published var target: MapMarker?
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func number(_ key: String, fallback: Double, range: ClosedRange<Double>) -> Double {
            guard let value = defaults.object(forKey: key) as? Double, value.isFinite else { return fallback }
            return min(range.upperBound, max(range.lowerBound, value))
        }
        x = number(MapPreferenceKeys.x, fallback: 32369, range: 0...65535)
        y = number(MapPreferenceKeys.y, fallback: 32241, range: 0...65535)
        floor = Int(number(MapPreferenceKeys.floor, fallback: 7, range: 0...15))
        zoom = number(MapPreferenceKeys.zoom, fallback: 2, range: 0.5...16)
    }
    func focus(_ marker: MapMarker) {
        x = Double(min(marker.x, 65535)); y = Double(min(marker.y, 65535))
        floor = Int(min(marker.z, 15)); zoom = 4; target = marker
    }
    func move(x: Double, y: Double) {
        guard x.isFinite, y.isFinite else { return }
        self.x = min(65535, max(0, x)); self.y = min(65535, max(0, y))
    }
    func zoom(to value: Double) {
        guard value.isFinite else { return }
        zoom = min(16, max(0.5, value))
    }
}

struct MapViewer: View {
    let destination: URL
    @ObservedObject var navigation: MapNavigation
    @AppStorage("appLanguage") private var language = "system"
    @AppStorage(MapPreferenceKeys.showMarkers) private var showMarkers = true
    @AppStorage(MapPreferenceKeys.followsSystem) private var followsSystemScrolling = true
    @AppStorage(MapPreferenceKeys.naturalZoom) private var naturalZoom = true
    @State private var overlay = MarkerOverlay()
    @State private var refreshID = UUID()
    @State private var loadedID = UUID()
    @State private var tiles: [TileCoordinate: URL] = [:]
    @State private var loading = true
    @State private var error: String?
    @State private var xInput = "32369"
    @State private var yInput = "32241"
    var body: some View {
        let _ = language
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L.text("Explorar mapa")).font(.largeTitle.bold())
                    Text(L.text("Arraste para navegar · role para aproximar · andares +7 a −8")).foregroundStyle(.secondary)
                }
                Spacer()
                Button { refreshID = UUID() } label: { Image(systemName: "arrow.clockwise") }
                    .help(L.text("Atualizar visualização")).accessibilityLabel(L.text("Atualizar visualização"))
                Button { navigation.zoom(to: navigation.zoom / 1.5) } label: { Image(systemName: "minus.magnifyingglass") }
                Button { navigation.zoom(to: navigation.zoom * 1.5) } label: { Image(systemName: "plus.magnifyingglass") }
            }
            HStack {
                Text("X")
                TextField("X", text: $xInput).frame(width: 75)
                Text("Y")
                TextField("Y", text: $yInput).frame(width: 75)
                Button(L.text("Ir"), action: go)
                Spacer()
                Picker(L.text("Andar"), selection: $navigation.floor) {
                    ForEach(0..<16) { Text(MapFloor.label(for: $0)).tag($0) }
                }.frame(width: 135)
                if let target = navigation.target {
                    Button(L.text("Centralizar")) { navigation.focus(target); syncInputs() }
                }
            }.textFieldStyle(.roundedBorder)
            HStack(spacing: 18) {
                Toggle(L.text("Exibir marcações"), isOn: $showMarkers)
                Toggle(L.text("Seguir rolagem do macOS"), isOn: $followsSystemScrolling)
                Toggle(L.text("Zoom natural"), isOn: $naturalZoom).disabled(followsSystemScrolling)
            }.font(.callout)
            Text(L.text(followsSystemScrolling ? "A direção do zoom segue a rolagem do macOS. Desative para escolher Zoom natural manualmente." : "Zoom natural inverte o sentido da roda. A pinça e os botões de zoom mantêm o comportamento habitual."))
                .font(.caption).foregroundStyle(.secondary)
            ZStack {
                LocalMapCanvas(tiles: tiles, navigation: navigation, overlay: overlay,
                               showMarkers: showMarkers, followsSystemScrolling: followsSystemScrolling,
                               naturalZoom: naturalZoom, revision: loadedID)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                if loading { ProgressView(L.text("Carregando mapas…")).padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) }
                else if tiles.isEmpty {
                    Text(L.text("Nenhum mapa local encontrado. Escolha a pasta do minimapa ou atualize os mapas primeiro."))
                        .multilineTextAlignment(.center).padding(24).frame(maxWidth: 430)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }.frame(minHeight: 300)
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack {
                Text("X: \(Int(navigation.x))   Y: \(Int(navigation.y))   \(L.text("Andar")): \(MapFloor.label(for: navigation.floor))   ·   \(Int(navigation.zoom * 100))%")
                    .monospacedDigit()
                Spacer()
                if let target = navigation.target { Text(target.text).lineLimit(1) }
            }.font(.caption).foregroundStyle(.secondary)
            Text(showMarkers ? L.format("%d marcações carregadas · passe o mouse para ler a descrição.", overlay.count) : L.text("Marcações ocultas"))
                .font(.caption).foregroundStyle(.secondary)
            Text(L.text("O visualizador usa seus mapas locais e funciona sem abrir o Tibia."))
                .font(.caption).foregroundStyle(.secondary)
        }.padding(28)
        .task(id: "\(destination.path)-\(refreshID)") {
            loading = true
            error = nil
            let folder = destination
            let result = await Task.detached { () -> ([TileCoordinate: URL], MarkerOverlay, String?) in
                do {
                    let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    var index: [TileCoordinate: URL] = [:]
                    for file in files.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
                        guard let tile = TileCoordinate.parse(file.lastPathComponent) else { continue }
                        let info = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                        if info.isRegularFile == true, info.isSymbolicLink != true { index[tile] = file }
                    }
                    let markers = MarkerReader.load(folder: folder)
                    return (index, MarkerOverlay(markers: markers.markers), markers.error)
                } catch { return ([:], MarkerOverlay(), error.localizedDescription) }
            }.value
            guard !Task.isCancelled else { return }
            tiles = result.0; overlay = result.1; error = result.2; loadedID = UUID(); loading = false
            syncInputs()
        }
        .onChange(of: navigation.target?.id) { _ in syncInputs() }
        .onChange(of: navigation.x) { _ in syncInputs() }
        .onChange(of: navigation.y) { _ in syncInputs() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refreshID = UUID() }
    }
    private func syncInputs() { xInput = String(Int(navigation.x)); yInput = String(Int(navigation.y)) }
    private func go() {
        guard let x = Int(xInput), let y = Int(yInput), (0...65535).contains(x), (0...65535).contains(y) else {
            error = L.text("Coordenadas inválidas. Use X e Y entre 0 e 65535."); return
        }
        error = nil
        navigation.move(x: Double(x), y: Double(y))
    }
}

struct LocalMapCanvas: NSViewRepresentable {
    let tiles: [TileCoordinate: URL]
    @ObservedObject var navigation: MapNavigation
    let overlay: MarkerOverlay
    let showMarkers: Bool
    let followsSystemScrolling: Bool
    let naturalZoom: Bool
    let revision: UUID
    func makeNSView(context: Context) -> TileCanvas {
        let view = TileCanvas()
        view.navigation = navigation
        return view
    }
    func updateNSView(_ view: TileCanvas, context: Context) {
        if view.revision != revision { view.cache.removeAllObjects(); view.tiles = tiles; view.revision = revision }
        view.overlay = overlay
        view.showMarkers = showMarkers
        view.followsSystemScrolling = followsSystemScrolling
        view.naturalZoom = naturalZoom
        view.navigation = navigation
        view.needsDisplay = true
    }
}

final class TileCanvas: NSView {
    var tiles: [TileCoordinate: URL] = [:]
    var navigation: MapNavigation!
    let cache = NSCache<NSURL, NSImage>()
    var overlay = MarkerOverlay()
    var showMarkers = true
    var followsSystemScrolling = true
    var naturalZoom = true
    var revision: UUID?
    private var markerTooltips: [NSView.ToolTipTag: String] = [:]
    private(set) var renderedMarkerCount = 0
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        cache.countLimit = 128
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Tibia map")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.055, alpha: 1).setFill(); bounds.fill()
        guard let n = navigation else { return }
        let zoom = n.zoom
        let left = n.x - bounds.width / (2 * zoom)
        let top = n.y - bounds.height / (2 * zoom)
        let firstX = Int(floor(left / 256)) * 256
        let firstY = Int(floor(top / 256)) * 256
        let lastX = Int(ceil((left + bounds.width / zoom) / 256)) * 256
        let lastY = Int(ceil((top + bounds.height / zoom) / 256)) * 256
        var visible = false
        for y in stride(from: firstY, through: lastY, by: 256) {
            for x in stride(from: firstX, through: lastX, by: 256) {
                guard let url = tiles[TileCoordinate(x: x, y: y, z: n.floor)] else { continue }
                let image: NSImage
                if let cached = cache.object(forKey: url as NSURL) { image = cached }
                else {
                    guard let loaded = MapTileImage.load(url) else { continue }
                    cache.setObject(loaded, forKey: url as NSURL); image = loaded
                }
                visible = true
                let rect = NSRect(x: (Double(x) - left) * zoom, y: (Double(y) - top) * zoom, width: 256 * zoom, height: 256 * zoom)
                image.draw(in: rect, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none])
            }
        }
        if !visible && !tiles.isEmpty {
            let message = L.text("Sem mapa nesta área ou andar.") as NSString
            message.draw(at: NSPoint(x: 20, y: 20), withAttributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 14)])
        }
        removeAllToolTips()
        markerTooltips.removeAll(keepingCapacity: true)
        renderedMarkerCount = 0
        if showMarkers {
            let world = CGRect(x: left - 14 / zoom, y: top - 14 / zoom,
                               width: (bounds.width + 28) / zoom, height: (bounds.height + 28) / zoom)
            for marker in overlay.visible(in: world, floor: n.floor) {
                let point = NSPoint(x: (Double(marker.x) + 0.5 - left) * zoom, y: (Double(marker.y) + 0.5 - top) * zoom)
                let rect = NSRect(x: point.x - 11, y: point.y - 11, width: 22, height: 22)
                MarkerIcon.image(for: marker.icon)?.draw(in: rect, from: .zero, operation: .sourceOver,
                                                       fraction: 1, respectFlipped: true,
                                                       hints: [.interpolation: NSImageInterpolation.none])
                let tag = addToolTip(rect.insetBy(dx: -3, dy: -3), owner: self, userData: nil)
                markerTooltips[tag] = "\(marker.text)\nX: \(marker.x) · Y: \(marker.y) · \(L.text("Andar")): \(MapFloor.label(for: Int(marker.z))) · \(L.text(marker.source))"
                renderedMarkerCount += 1
            }
        }
        if showMarkers, let target = n.target, target.z == UInt64(n.floor) {
            let point = NSPoint(x: (Double(target.x) + 0.5 - left) * zoom, y: (Double(target.y) + 0.5 - top) * zoom)
            NSColor.systemYellow.setStroke()
            let circle = NSBezierPath(ovalIn: NSRect(x: point.x - 10, y: point.y - 10, width: 20, height: 20))
            circle.lineWidth = 3; circle.stroke()
            let cross = NSBezierPath()
            cross.move(to: NSPoint(x: point.x-18, y: point.y)); cross.line(to: NSPoint(x: point.x+18, y: point.y))
            cross.move(to: NSPoint(x: point.x, y: point.y-18)); cross.line(to: NSPoint(x: point.x, y: point.y+18))
            cross.lineWidth = 1; cross.stroke()
        }
        setAccessibilityValue("X \(Int(n.x)), Y \(Int(n.y)), \(L.text("Andar")) \(MapFloor.label(for: n.floor)). " + L.format("%d marcações visíveis", renderedMarkerCount))
    }
    @objc func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData: UnsafeMutableRawPointer?) -> String {
        markerTooltips[tag] ?? ""
    }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
    override func mouseDragged(with event: NSEvent) {
        navigation.move(x: navigation.x - event.deltaX / navigation.zoom, y: navigation.y - event.deltaY / navigation.zoom)
    }
    override func scrollWheel(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let old = navigation.zoom
        let factor = MapZoomPolicy.factor(delta: event.scrollingDeltaY, invertedFromDevice: event.isDirectionInvertedFromDevice,
                                          followsSystem: followsSystemScrolling, natural: naturalZoom,
                                          precise: event.hasPreciseScrollingDeltas)
        navigation.zoom(to: old * factor)
        navigation.move(x: navigation.x + (point.x - bounds.midX) * (1 / old - 1 / navigation.zoom),
                        y: navigation.y + (point.y - bounds.midY) * (1 / old - 1 / navigation.zoom))
    }
    override func magnify(with event: NSEvent) { navigation.zoom(to: navigation.zoom * (1 + event.magnification)) }
    override func keyDown(with event: NSEvent) {
        let step = 60 / navigation.zoom
        switch event.keyCode {
        case 123: navigation.move(x: navigation.x-step, y: navigation.y)
        case 124: navigation.move(x: navigation.x+step, y: navigation.y)
        case 125: navigation.move(x: navigation.x, y: navigation.y+step)
        case 126: navigation.move(x: navigation.x, y: navigation.y-step)
        default: super.keyDown(with: event)
        }
    }
}

/// Tibia PNGs may declare 96 dpi; use pixel dimensions, never point dimensions.
enum MapTileImage {
    static func load(_ url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == 256, image.height == 256 else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: 256, height: 256))
    }
}
