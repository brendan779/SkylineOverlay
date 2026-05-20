import SwiftUI

/// A row of RCOU motor bars — one per channel the user has configured for
/// the Motors widget. Each bar spans the 1000–2000 µs PWM range filled from
/// the bottom, with the channel's label beneath, and fades on its own when
/// that channel goes quiet.
///
/// Width is driven by the layout (the widget grows wider with more
/// channels), so the bars themselves stay a consistent visual size.
struct MotorBarWidget: View {
    var settings: WidgetSettings
    var theme: OverlayTheme
    var motors: [TelemetrySample.MotorBar]
    var size: CGSize

    var body: some View {
        Canvas { ctx, sz in draw(&ctx, sz) }
            .frame(width: size.width, height: size.height)
    }

    private func draw(_ ctx: inout GraphicsContext, _ sz: CGSize) {
        let w = sz.width, h = sz.height
        let panel = Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h),
                         cornerRadius: min(w, h) * 0.10)
        ctx.fill(panel, with: .color(settings.background.color))
        ctx.stroke(panel, with: .color(.white.opacity(0.22)), lineWidth: 1)

        ctx.draw(Text("MOTORS").font(.hud(h * 0.085))
                    .foregroundStyle(theme.label.color),
                 at: CGPoint(x: w / 2, y: h * 0.10), anchor: .center)

        guard !motors.isEmpty else { return }

        let count = CGFloat(motors.count)
        let sidePad = w * 0.10
        let avail = max(0, w - 2 * sidePad)
        // Reserve ~25% of the lane for gaps; the rest is bar.
        let lane = avail / count
        let bw = max(4, lane * 0.75)
        let y0 = h * 0.22, y1 = h * 0.78

        for (i, motor) in motors.enumerated() {
            let cx = sidePad + lane * (CGFloat(i) + 0.5)
            drawBar(&ctx, cx: cx, bw: bw, y0: y0, y1: y1, h: h, motor: motor)
        }
    }

    private func drawBar(_ ctx: inout GraphicsContext,
                         cx: CGFloat, bw: CGFloat,
                         y0: CGFloat, y1: CGFloat, h: CGFloat,
                         motor: TelemetrySample.MotorBar) {
        var layer = ctx
        layer.opacity = motor.opacity

        let x = cx - bw / 2
        let trackH = y1 - y0
        layer.fill(Path(roundedRect: CGRect(x: x, y: y0, width: bw, height: trackH),
                        cornerRadius: bw / 2),
                   with: .color(.white.opacity(0.10)))

        let frac = max(0.0, min(1.0, (motor.value - 1000) / 1000))
        let fillH = frac * trackH
        if fillH > 1 {
            layer.fill(Path(roundedRect: CGRect(x: x, y: y1 - fillH,
                                                width: bw, height: fillH),
                            cornerRadius: bw / 2),
                       with: .color(settings.accent.color))
        }

        layer.draw(Text(motor.label).font(.hud(h * 0.085))
                    .foregroundStyle(theme.label.color),
                   at: CGPoint(x: cx, y: y1 + h * 0.11), anchor: .center)
    }
}
