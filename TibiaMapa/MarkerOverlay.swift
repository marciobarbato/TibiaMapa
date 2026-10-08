import Foundation

/// Normal/private files often repeat the same record. Deduplicate only exact
/// semantic duplicates, retaining distinct descriptions/icons at one location.
struct MarkerOverlay {
    private struct Key: Hashable {
        let x: UInt64
        let y: UInt64
        let z: UInt64
        let icon: UInt64
        let text: String
    }
    private var buckets: [TileCoordinate: [MapMarker]] = [:]
    let count: Int
    init(markers: [MapMarker] = []) {
        var seen: Set<Key> = []
        for marker in markers where marker.x <= 65535 && marker.y <= 65535 && marker.z <= 15 {
            let key = Key(x: marker.x, y: marker.y, z: marker.z, icon: marker.icon, text: marker.text)
            guard seen.insert(key).inserted else { continue }
            let tile = TileCoordinate(x: Int(marker.x) / 256 * 256, y: Int(marker.y) / 256 * 256, z: Int(marker.z))
            buckets[tile, default: []].append(marker)
        }
        count = seen.count
    }
    func visible(in bounds: CGRect, floor: Int) -> [MapMarker] {
        guard !bounds.isEmpty, (0...15).contains(floor) else { return [] }
        let minX = max(0, Int(Foundation.floor(bounds.minX / 256)) * 256)
        let maxX = min(65280, Int(Foundation.floor(bounds.maxX / 256)) * 256)
        let minY = max(0, Int(Foundation.floor(bounds.minY / 256)) * 256)
        let maxY = min(65280, Int(Foundation.floor(bounds.maxY / 256)) * 256)
        guard minX <= maxX, minY <= maxY else { return [] }
        var result: [MapMarker] = []
        for y in stride(from: minY, through: maxY, by: 256) {
            for x in stride(from: minX, through: maxX, by: 256) {
                result += (buckets[TileCoordinate(x: x, y: y, z: floor)] ?? []).filter {
                    bounds.contains(CGPoint(x: Double($0.x) + 0.5, y: Double($0.y) + 0.5))
                }
            }
        }
        return result
    }
}
