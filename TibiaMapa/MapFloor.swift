import Foundation

/// Display height relative to the surface. Stored Tibia coordinates stay 0...15.
enum MapFloor {
    static func label(for coordinate: Int) -> String {
        let level = 7 - coordinate
        return level > 0 ? "+\(level)" : String(level)
    }
}
