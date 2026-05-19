import SwiftUI

/// Straight-line ground distance from the home position, with an optional
/// max-reached sub-label.
struct DistanceWidget: View {
    var settings: WidgetSettings
    var theme: OverlayTheme
    var distance: Double        // m
    var maxDistance: Double     // m
    var unit: DistanceUnit
    var showMax: Bool
    var hasHome: Bool
    var size: CGSize

    var body: some View {
        Canvas { ctx, sz in draw(&ctx, sz) }
            .frame(width: size.width, height: size.height)
    }

    private func draw(_ ctx: inout GraphicsContext, _ sz: CGSize) {
        let w = sz.width, h = sz.height

        let panel = Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h),
                         cornerRadius: h * 0.20)
        ctx.fill(panel, with: .color(settings.background.color))
        ctx.stroke(panel, with: .color(.white.opacity(0.22)), lineWidth: 1)

        ctx.draw(Text("DIST HOME").font(.hud(h * 0.165))
                    .foregroundStyle(theme.label.color),
                 at: CGPoint(x: w / 2, y: h * 0.21), anchor: .center)

        let valueY = showMax ? h * 0.54 : h * 0.62
        let value = Text(hasHome
                            ? String(format: "%.0f", unit.convert(distance))
                            : "—")
            .font(.hud(h * 0.38, weight: .semibold))
            .foregroundStyle(settings.accent.color)
            + Text(" \(unit.label)").font(.hud(h * 0.20))
            .foregroundStyle(theme.label.color)
        ctx.draw(value, at: CGPoint(x: w / 2, y: valueY), anchor: .center)

        if showMax {
            let maxText = hasHome
                ? "MAX \(Int(unit.convert(maxDistance).rounded())) \(unit.label)"
                : "MAX —"
            ctx.draw(Text(maxText).font(.hud(h * 0.135))
                        .foregroundStyle(.white.opacity(0.5)),
                     at: CGPoint(x: w / 2, y: h * 0.85), anchor: .center)
        }
    }
}
