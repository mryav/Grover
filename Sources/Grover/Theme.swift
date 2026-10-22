import AppKit
import CoreText
import SwiftUI

/// Design tokens from the Grover Figma file.
enum Theme {
    // Window sizes per mode (the window is not user-resizable).
    static let compactSize = NSSize(width: 400, height: 89)
    static let expandedSize = NSSize(width: 400, height: 500)
    static let splitSize = NSSize(width: 900, height: 500)

    /// Width of the left (Google) column inside the 1pt border + 8pt padding.
    static let columnWidth: CGFloat = expandedSize.width - 18

    /// The side page's frame in split mode. Prefetched pages are laid out at this
    /// size while hidden so they appear without reflowing.
    static let sidePageSize = NSSize(
        width: splitSize.width - 18 - columnWidth - 8,
        height: splitSize.height - 18
    )

    /// Hairline outline used for the window and the search bar.
    static let strokeWidth: CGFloat = 0.5
    static let border = Color(hex: 0xA9A9A9)
    static let borderDarkEmbedded = Color(hex: 0x545454)
    static let placeholder = Color(hex: 0x797979)
    static let googleLight = Color.white
    static let googleDark = Color(hex: 0x22242B)

    static func searchFont() -> Font {
        if let font = NSFont(name: "Inter-Medium", size: 16) ?? NSFont(name: "Inter Medium", size: 16) {
            return Font(font)
        }
        return .system(size: 16, weight: .medium)
    }

    static let searchTracking: CGFloat = -0.32

    // MARK: Resources

    /// Resources live in Grover.app/Contents/Resources; when run via `swift run`
    /// fall back to the repo's Resources folder.
    static func resourceURL(_ name: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: nil) {
            return url
        }
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources").appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: repo.path) ? repo : nil
    }

    private static var imageCache: [String: NSImage] = [:]

    static func image(_ name: String) -> NSImage {
        if let cached = imageCache[name] { return cached }
        let image = resourceURL(name).flatMap(NSImage.init(contentsOf:)) ?? NSImage()
        imageCache[name] = image
        return image
    }

    static func registerFonts() {
        guard let url = resourceURL("Inter-Medium.ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
