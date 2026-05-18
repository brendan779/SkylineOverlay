import SwiftUI

extension Font {
    /// The HUD typeface — bundled Barlow Condensed, registered at launch.
    /// Falls back to the system font if registration ever fails.
    static func hud(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .custom("Barlow Condensed", size: size).weight(weight)
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
