import SwiftUI

/// Vertical-speed bar — a centre-zero track filled toward climb or descent,
/// clamped to ±5 m/s full scale, with the value below.
struct VerticalSpeedWidget: View {
    var settings: WidgetSettings
    var theme: OverlayTheme
    var verticalSpeed: Double
    var size: CGSize

    var body: some View {
        Canvas { ctx, sz in draw(&ctx, sz) }
            .frame(width: size.width, height: size.height)
    }

    private func draw(_ ctx: inout GraphicsContext, _ sz: CGSize) {
        let w = sz.width, h = sz.height
        let accent = settings.accent.color
        let panel = Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h),
                         cornerRadius: w * 0.22)
        ctx.fill(panel, with: .color(settings.background.color))
        ctx.stroke(panel, with: .color(.white.opacity(0.22)), lineWidth: 1)

        ctx.draw(Text("V/S").font(.hud(h * 0.09))
                    .foregroundStyle(theme.label.color),
                 at: CGPoint(x: w / 2, y: h * 0.08), anchor: .center)

        let trackW = w * 0.20
        let trackX = w / 2 - trackW / 2
        let y0 = h * 0.18, y1 = h * 0.82
        let trackH = y1 - y0
        let mid = (y0 + y1) / 2
        ctx.fill(Path(roundedRect: CGRect(x: trackX, y: y0,
                                          width: trackW, height: trackH),
                      cornerRadius: trackW / 2),
                 with: .color(.white.opacity(0.10)))

        let frac = max(-1.0, min(1.0, verticalSpeed / 5.0))
        let fillH = abs(frac) * trackH / 2
        if fillH > 1 {
            let fy = frac >= 0 ? mid - fillH : mid
            ctx.fill(Path(roundedRect: CGRect(x: trackX, y: fy,
                                              width: trackW, height: fillH),
                          cornerRadius: trackW / 2),
                     with: .color(accent))
        }
        ctx.stroke(segment(trackX - w * 0.12, mid, trackX + trackW + w * 0.12, mid),
                   with: .color(.white.opacity(0.4)), lineWidth: 1)

        ctx.draw(Text(String(format: "%+.1f", verticalSpeed))
                    .font(.hud(h * 0.09, weight: .semibold))
                    .foregroundStyle(accent),
                 at: CGPoint(x: w / 2, y: h * 0.93), anchor: .center)
    }
}
