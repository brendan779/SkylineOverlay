import SwiftUI

/// Horizontal heading ribbon — tick marks every 5°, cardinal letters and
/// three-digit degrees at every 10°, with a centre cursor.
struct HeadingCompassWidget: View {
    var settings: WidgetSettings
    var theme: OverlayTheme
    var heading: Double
    var size: CGSize

    private let cardinals: [Int: String] = [
        0: "N", 45: "NE", 90: "E", 135: "SE",
        180: "S", 225: "SW", 270: "W", 315: "NW",
    ]

    var body: some View {
        Canvas { ctx, sz in draw(&ctx, sz) }
            .frame(width: size.width, height: size.height)
    }

    private func draw(_ ctx: inout GraphicsContext, _ sz: CGSize) {
        let w = sz.width, h = sz.height
        let cx = w / 2
        let accent = settings.accent.color
        let panel = Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h),
                         cornerRadius: h * 0.22)
        ctx.fill(panel, with: .color(settings.background.color))

        var content = ctx
        content.clip(to: panel)
        let pxPerDeg = w / 80.0

        for off in stride(from: -45, through: 45, by: 1) {
            let deg = (Int(heading.rounded()) + off + 3600) % 360
            guard deg % 5 == 0 else { continue }
            let x = cx + CGFloat(off) * pxPerDeg
            guard x >= 2, x <= w - 2 else { continue }
            let major = deg % 10 == 0
            content.stroke(segment(x, 0, x, major ? h * 0.34 : h * 0.18),
                           with: .color(.white.opacity(major ? 0.6 : 0.3)),
                           lineWidth: 1)
            if major {
                let card = cardinals[deg]
                let text = card ?? String(format: "%03d", deg)
                let font = Font.hud(card != nil ? h * 0.44 : h * 0.34,
                                    weight: card != nil ? .semibold : .regular)
                content.draw(Text(text).font(font)
                                .foregroundStyle(card != nil
                                                 ? accent : .white.opacity(0.7)),
                             at: CGPoint(x: x, y: h * 0.66), anchor: .center)
            }
        }

        content.stroke(segment(cx, 0, cx, h),
                       with: .color(accent.opacity(0.7)), lineWidth: 1)
        var caret = Path()
        caret.move(to: CGPoint(x: cx, y: h * 0.32))
        caret.addLine(to: CGPoint(x: cx - h * 0.17, y: 0))
        caret.addLine(to: CGPoint(x: cx + h * 0.17, y: 0))
        caret.closeSubpath()
        content.fill(caret, with: .color(accent))

        ctx.stroke(panel, with: .color(.white.opacity(0.22)), lineWidth: 1)
    }
}
