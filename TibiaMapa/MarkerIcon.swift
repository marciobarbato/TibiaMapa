import SwiftUI
import ImageIO

/// Tibia's marker IDs are not in the same order as the sprite sheet.
/// See ThirdPartyNotices.txt for the artwork source and attribution.
@MainActor
enum MarkerIcon {
    static let slots = [0, 1, 2, 3, 4, 5, 6, 11, 12, 13, 14, 15, 16, 17, 7, 18, 8, 19, 9, 20]
    private static let images: [NSImage] = {
        guard let url = Bundle.main.url(forResource: "MinimapSymbols", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil),
              sheet.width == 121, sheet.height == 22 else { return [] }
        return slots.compactMap { slot in
            guard let glyph = sheet.cropping(to: CGRect(x: slot % 11 * 11, y: slot / 11 * 11, width: 11, height: 11)) else { return nil }
            return NSImage(cgImage: glyph, size: NSSize(width: 11, height: 11))
        }
    }()
    static func image(for id: UInt64) -> NSImage? {
        guard images.count == 20 else { return nil }
        return images[id < 20 ? Int(id) : 1]
    }
}

struct MarkerIconView: View {
    let id: UInt64
    var body: some View {
        if let image = MarkerIcon.image(for: id) {
            Image(nsImage: image).resizable().interpolation(.none).frame(width: 22, height: 22)
                .accessibilityLabel(L.text("Ícone") + " \(id)")
        } else {
            Image(systemName: "questionmark.square.fill")
        }
    }
}
