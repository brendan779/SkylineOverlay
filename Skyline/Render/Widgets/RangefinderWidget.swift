import SwiftUI

/// Rangefinder height above ground. The whole widget fades out when the log
/// carries no recent reading — so it only shows while the sensor is live.
struct RangefinderWidget: View {
    var settings: WidgetSettings
    var theme: OverlayTheme
    var distance: Double        // m AGL
    var dataOpacity: Double     // 0 when readings have stopped
    var size: CGSize

    var body: some View {
        Canvas { ctx, sz in draw(&ctx, sz) }
            .frame(width: size.width, height: size.height)
    }

    private func draw(_ ctx: inout GraphicsContext, _ sz: CGSize) {
        ctx.opacity = dataOpacity

        let w = sz.width, h = sz.height
        let panel = Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h),
                         cornerRadius: h * 0.24)
        ctx.fill(panel, with: .color(settings.background.color))
        ctx.stroke(panel, with: .color(.white.opacity(0.22)), lineWidth: 1)

        ctx.draw(Text("AGL").font(.hud(h * 0.19))
                    .foregroundStyle(theme.label.color),
                 at: CGPoint(x: w / 2, y: h * 0.27), anchor: .center)

        let value = Text(String(format: "%.1f", distance))
            .font(.hud(h * 0.40, weight: .semibold))
            .foregroundStyle(settings.accent.color)
            + Text(" m").font(.hud(h * 0.24))
            .foregroundStyle(theme.label.color)
        ctx.draw(value, at: CGPoint(x: w / 2, y: h * 0.64), anchor: .center)
    }
}
