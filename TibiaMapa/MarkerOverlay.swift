import Foundation

enum MarkerDisplayMode: String, CaseIterable, Identifiable {
    case all, normal, privateMarkers, none

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return L.text("Todas")
        case .normal: return L.text("Originais do jogo")
        case .privateMarkers: return L.text("Privadas")
        case .none: return L.text("Nenhuma")
        }
    }
    func includes(_ marker: MapMarker) -> Bool {
        switch self {
        case .all: return true
        case .normal: return marker.source == "Normal"
        case .privateMarkers: return marker.source == "Privada"
        case .none: return false
        }
    }
}

/// Separate indexes keep private markers available even when the normal file
/// contains an identical record. Neither marker file is changed.
struct MarkerOverlay {
    private struct Key: Hashable {
        let x: UInt64
        let y: UInt64
        let z: UInt64
        let icon: UInt64
        let text: String
    }
    private struct Index {
        var buckets: [TileCoordinate: [MapMarker]] = [:]
        var count = 0
    }
    private var indexes: [MarkerDisplayMode: Index] = [:]
    var count: Int { count(for: .all) }

    init(markers: [MapMarker] = []) {
        for mode in [MarkerDisplayMode.all, .normal, .privateMarkers] {
            var seen: Set<Key> = []
            var index = Index()
            for marker in markers where marker.x <= 65535 && marker.y <= 65535 && marker.z <= 15 && mode.includes(marker) {
                let key = Key(x: marker.x, y: marker.y, z: marker.z, icon: marker.icon, text: marker.text)
                guard seen.insert(key).inserted else { continue }
                let tile = TileCoordinate(x: Int(marker.x) / 256 * 256, y: Int(marker.y) / 256 * 256, z: Int(marker.z))
                index.buckets[tile, default: []].append(marker)
                index.count += 1
            }
            indexes[mode] = index
        }
    }
    func count(for mode: MarkerDisplayMode) -> Int { indexes[mode]?.count ?? 0 }
    func visible(in bounds: CGRect, floor: Int, mode: MarkerDisplayMode = .all) -> [MapMarker] {
        guard !bounds.isEmpty, (0...15).contains(floor), let index = indexes[mode] else { return [] }
        let minX = max(0, Int(Foundation.floor(bounds.minX / 256)) * 256)
        let maxX = min(65280, Int(Foundation.floor(bounds.maxX / 256)) * 256)
        let minY = max(0, Int(Foundation.floor(bounds.minY / 256)) * 256)
        let maxY = min(65280, Int(Foundation.floor(bounds.maxY / 256)) * 256)
        guard minX <= maxX, minY <= maxY else { return [] }
        var result: [MapMarker] = []
        for y in stride(from: minY, through: maxY, by: 256) {
            for x in stride(from: minX, through: maxX, by: 256) {
                result += (index.buckets[TileCoordinate(x: x, y: y, z: floor)] ?? []).filter {
                    bounds.contains(CGPoint(x: Double($0.x) + 0.5, y: Double($0.y) + 0.5))
                }
            }
        }
        return result
    }
}
