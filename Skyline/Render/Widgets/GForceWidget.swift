import SwiftUI

/// G-force meter — a ball-in-circle showing the 2-axis lateral load, with a
/// numeric peak readout below.
///
/// The ball sits at the accelerometer's X/Y load scaled to `maxG`; its
/// displacement is clamped to the rim so a hard pull pins to the edge.
struct GForceWidget: View {
    var settings: WidgetSettings
    var theme: OverlayTheme
    var gForce: TelemetrySample.GForce
    var maxG: Double            // full-scale deflection, ±g
    var hasData: Bool
    /// Threshold colour for the current lateral load, or nil for the accent.
    var thresholdColor: Color? = nil
    var size: CGSize

    var body: some View {
        Canvas { ctx, sz in draw(&ctx, sz) }
            .frame(width: size.width, height: size.height)
    }

    private func draw(_ ctx: inout GraphicsContext, _ sz: CGSize) {
        let w = sz.width, h = sz.height
        let accent = thresholdColor ?? settings.accent.color

        // Panel
        let panel = Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h),
                         cornerRadius: h * 0.10)
        ctx.fill(panel, with: .color(settings.background.color))
        ctx.stroke(panel, with: .color(.white.opacity(0.22)), lineWidth: 1)

        // Label
        ctx.draw(Text("G-FORCE").font(.hud(h * 0.085))
                    .foregroundStyle(theme.label.color),
                 at: CGPoint(x: w / 2, y: h * 0.085), anchor: .center)

        // Dial
        let center = CGPoint(x: w / 2, y: h * 0.42)
        let radius = w * 0.37

        for ring in [1.0, 0.5] {
            let r = radius * ring
            ctx.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r,
                                              width: r * 2, height: r * 2)),
                       with: .color(.white.opacity(ring == 1 ? 0.45 : 0.18)),
                       lineWidth: 1)
        }
        // Crosshair
        ctx.stroke(segment(center.x - radius, center.y, center.x + radius, center.y),
                   with: .color(.white.opacity(0.18)), lineWidth: 1)
        ctx.stroke(segment(center.x, center.y - radius, center.x, center.y + radius),
                   with: .color(.white.opacity(0.18)), lineWidth: 1)

        // Scale tick label
        ctx.draw(Text(String(format: "%.0fg", maxG)).font(.hud(h * 0.07))
                    .foregroundStyle(.white.opacity(0.5)),
                 at: CGPoint(x: center.x + radius - 2, y: center.y - h * 0.045),
                 anchor: .trailing)

        // Ball — lateral Y drives screen X, lateral X (forward) drives -Y.
        if hasData, maxG > 0 {
            var dx = gForce.lateralY / maxG
            var dy = -gForce.lateralX / maxG
            let m = (dx * dx + dy * dy).squareRoot()
            if m > 1 { dx /= m; dy /= m }
            let ball = CGPoint(x: center.x + dx * radius,
                               y: center.y + dy * radius)
            let br = w * 0.07
            ctx.stroke(segment(center.x, center.y, ball.x, ball.y),
                       with: .color(accent.opacity(0.4)), lineWidth: 1.5)
            ctx.fill(Path(ellipseIn: CGRect(x: ball.x - br, y: ball.y - br,
                                            width: br * 2, height: br * 2)),
                     with: .color(accent))
        }

        // Peak readout
        ctx.draw(Text("PEAK").font(.hud(h * 0.075))
                    .foregroundStyle(theme.label.color),
                 at: CGPoint(x: w / 2, y: h * 0.80), anchor: .center)
        let peak = Text(hasData ? String(format: "%.2f", gForce.peakLateral) : "—")
            .font(.hud(h * 0.16, weight: .semibold))
            .foregroundStyle(.white)
            + Text(" g").font(.hud(h * 0.09))
            .foregroundStyle(theme.label.color)
        ctx.draw(peak, at: CGPoint(x: w / 2, y: h * 0.91), anchor: .center)
    }
}
