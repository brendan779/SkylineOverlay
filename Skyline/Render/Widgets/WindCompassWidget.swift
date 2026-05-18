import SwiftUI

/// Body-frame wind compass — a fixed aircraft silhouette (nose up) inside a
/// ring, with an accent arrow showing where the wind blows *from* relative
/// to the aircraft, and the wind speed below.
struct WindCompassWidget: View {
    var settings: WidgetSettings
    var theme: OverlayTheme
    var windVN: Double
    var windVE: Double
    var yaw: Double
    var hasWind: Bool
    var speedUnit: SpeedUnit
    var size: CGSize

    var body: some View {
        Canvas { ctx, sz in draw(&ctx, sz) }
            .frame(width: size.width, height: size.height)
    }

    private func draw(_ ctx: inout GraphicsContext, _ sz: CGSize) {
        let w = sz.width, h = sz.height
        let accent = settings.accent.color
        let panel = Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h),
                         cornerRadius: h * 0.12)
        ctx.fill(panel, with: .color(settings.background.color))
        ctx.stroke(panel, with: .color(.white.opacity(0.22)), lineWidth: 1)

        ctx.draw(Text("WIND").font(.hud(h * 0.10))
                    .foregroundStyle(theme.label.color),
                 at: CGPoint(x: w / 2, y: h * 0.09), anchor: .center)

        let cx = w / 2, cy = h * 0.52
        let r = min(w, h * 0.82) / 2 - h * 0.06

        ctx.stroke(Path(ellipseIn: CGRect(x: cx - r, y: cy - r,
                                          width: 2 * r, height: 2 * r)),
                   with: .color(.white.opacity(0.3)), lineWidth: 1.5)
        for d in stride(from: 0, to: 360, by: 45) {
            let ang = Double(d - 90) * .pi / 180
            let long = d % 90 == 0
            let ri = r * (long ? 0.84 : 0.90)
            ctx.stroke(segment(cx + CGFloat(cos(ang)) * ri,
                               cy + CGFloat(sin(ang)) * ri,
                               cx + CGFloat(cos(ang)) * r,
                               cy + CGFloat(sin(ang)) * r),
                       with: .color(.white.opacity(long ? 0.5 : 0.3)),
                       lineWidth: long ? 2 : 1)
        }

        // Aircraft silhouette, viewed from above, nose up.
        let s = r / 60
        func P(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: cx + CGFloat(x) * s, y: cy + CGFloat(y) * s)
        }
        let body = Color.white.opacity(0.85)
        ctx.fill(Path(CGRect(x: P(-2, -22).x, y: P(-2, -22).y,
                             width: 4 * s, height: 36 * s)), with: .color(body))
        var wings = Path()
        wings.move(to: P(-26, -2)); wings.addLine(to: P(26, -2))
        wings.addLine(to: P(22, 5)); wings.addLine(to: P(-22, 5))
        wings.closeSubpath()
        ctx.fill(wings, with: .color(body))
        var tail = Path()
        tail.move(to: P(-9, 12)); tail.addLine(to: P(9, 12))
        tail.addLine(to: P(6, 17)); tail.addLine(to: P(-6, 17))
        tail.closeSubpath()
        ctx.fill(tail, with: .color(body))

        // Wind arrow — points from the "from" bearing inward.
        if hasWind {
            let earthFrom = atan2(-windVE, -windVN) * 180 / .pi
            let ang = (earthFrom - yaw - 90) * .pi / 180
            let dir = CGPoint(x: CGFloat(cos(ang)), y: CGFloat(sin(ang)))
            let from = CGPoint(x: cx + dir.x * r, y: cy + dir.y * r)
            let tip = CGPoint(x: cx + dir.x * r * 0.38, y: cy + dir.y * r * 0.38)
            let back = CGPoint(x: cx + dir.x * r * 0.58, y: cy + dir.y * r * 0.58)
            ctx.stroke(segment(from.x, from.y, back.x, back.y),
                       with: .color(accent), lineWidth: max(2, r * 0.07))
            let perp = ang + .pi / 2
            let hw = r * 0.17
            var head = Path()
            head.move(to: tip)
            head.addLine(to: CGPoint(x: back.x + CGFloat(cos(perp)) * hw,
                                     y: back.y + CGFloat(sin(perp)) * hw))
            head.addLine(to: CGPoint(x: back.x - CGFloat(cos(perp)) * hw,
                                     y: back.y - CGFloat(sin(perp)) * hw))
            head.closeSubpath()
            ctx.fill(head, with: .color(accent))
            let dr = max(2, r * 0.08)
            ctx.fill(Path(ellipseIn: CGRect(x: from.x - dr, y: from.y - dr,
                                            width: 2 * dr, height: 2 * dr)),
                     with: .color(accent))
        }

        // Speed readout.
        let speed = (windVN * windVN + windVE * windVE).squareRoot()
        let text = hasWind
            ? String(format: "%.0f %@", speedUnit.convert(speed), speedUnit.label)
            : "—"
        ctx.draw(Text(text).font(.hud(h * 0.12, weight: .semibold))
                    .foregroundStyle(.white),
                 at: CGPoint(x: cx, y: cy + r + h * 0.05), anchor: .center)
    }
}
