import SwiftUI

extension Font {
    /// Condensed HUD font. Uses a system condensed face until the bundled
    /// Barlow Condensed is registered (Stage 6).
    static func hud(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }
}

/// A straight-line `Path` between two points.
func segment(_ x0: CGFloat, _ y0: CGFloat,
             _ x1: CGFloat, _ y1: CGFloat) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: x0, y: y0))
    p.addLine(to: CGPoint(x: x1, y: y1))
    return p
}
