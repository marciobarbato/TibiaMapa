import Foundation

/// AppKit has already applied macOS natural scrolling to scrollingDeltaY.
/// Only undo that adjustment when the user explicitly overrides the system.
enum MapZoomPolicy {
    static func factor(delta: Double, invertedFromDevice: Bool, followsSystem: Bool,
                       natural: Bool, precise: Bool) -> Double {
        guard delta.isFinite else { return 1 }
        let physicalDelta = invertedFromDevice ? -delta : delta
        let directedDelta = followsSystem ? delta : (natural ? -physicalDelta : physicalDelta)
        let exponent = directedDelta * (precise ? 0.015 : 0.12)
        return exp(min(2, max(-2, exponent)))
    }
}

enum MapPreferenceKeys {
    static let showMarkers = "viewer.showMarkers"
    static let markerDisplay = "viewer.markerDisplay"
    static let followsSystem = "viewer.followsSystemScrolling"
    static let naturalZoom = "viewer.naturalZoom"
    static let x = "viewer.centerX"
    static let y = "viewer.centerY"
    static let floor = "viewer.floor"
    static let zoom = "viewer.zoom"
    static let destination = "minimapDestination"
    static let style = "mapStyle"
    static let preserveMarkers = "preserveMarkers"
    static let makeBackup = "makeBackup"
}
