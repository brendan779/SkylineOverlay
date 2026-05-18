import SwiftUI
import AppKit

/// An RGBA colour stored as components in 0...1.
///
/// Kept as plain components (not SwiftUI `Color`) so it is `Codable` for
/// presets and matches the renderer's colour model. `color` bridges to
/// SwiftUI for display and the Inspector's colour pickers.
struct RGBAColor: Codable, Equatable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Bridge from a SwiftUI `Color` (used by the Inspector's `ColorPicker`).
    init(_ color: Color) {
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(Double(resolved.redComponent),
                  Double(resolved.greenComponent),
                  Double(resolved.blueComponent),
                  Double(resolved.alphaComponent))
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    /// The same colour with a different alpha.
    func opacity(_ a: Double) -> RGBAColor {
        RGBAColor(red, green, blue, a)
    }

    static let white = RGBAColor(1, 1, 1)
    static let black = RGBAColor(0, 0, 0)
}
