import SwiftUI

/// Five RCOU motor bars in one widget — the throttle (servo 5), set a little
/// apart on the left, and the four lift motors (servos 7–10) grouped tight on
/// the right. Each bar spans the 1000–2000 µs PWM range, filled from the
/// bottom, and fades out on its own once its channel goes quiet.
struct MotorBarWidget: View {
    var settings: WidgetSettings
    var theme: OverlayTheme
    var throttle: TelemetrySample.MotorBar
    var liftMotors: [TelemetrySample.MotorBar]
    var size: CGSize

    var body: some View {
        Canvas { ctx, sz in draw(&ctx, sz) }
            .frame(width: size.width, height: size.height)
    }

    private func draw(_ ctx: inout GraphicsContext, _ sz: CGSize) {
        let w = sz.width, h = sz.height
        let panel = Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h),
                         cornerRadius: w * 0.10)
        ctx.fill(panel, with: .color(settings.background.color))
        ctx.stroke(panel, with: .color(.white.opacity(0.22)), lineWidth: 1)

        ctx.draw(Text("MOTORS").font(.hud(h * 0.085))
                    .foregroundStyle(theme.label.color),
                 at: CGPoint(x: w / 2, y: h * 0.10), anchor: .center)

        let px = w * 0.09
        let avail = w - 2 * px
        let bw = avail * 0.135
        let gap = bw * 0.40
        let y0 = h * 0.22, y1 = h * 0.78

        // Throttle — alone on the left, with breathing room.
        drawBar(&ctx, cx: px + bw / 2, bw: bw, y0: y0, y1: y1, h: h,
                motor: throttle, label: "THR")

        // Lift motors — a tight group flush to the right edge.
        let groupWidth = CGFloat(liftMotors.count) * bw
            + CGFloat(max(0, liftMotors.count - 1)) * gap
        let groupLeft = px + avail - groupWidth
        for (i, motor) in liftMotors.enumerated() {
            let cx = groupLeft + bw / 2 + CGFloat(i) * (bw + gap)
            drawBar(&ctx, cx: cx, bw: bw, y0: y0, y1: y1, h: h,
                    motor: motor, label: "\(7 + i)")
        }
    }

    private func drawBar(_ ctx: inout GraphicsContext,
                         cx: CGFloat, bw: CGFloat,
                         y0: CGFloat, y1: CGFloat, h: CGFloat,
                         motor: TelemetrySample.MotorBar, label: String) {
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

        layer.draw(Text(label).font(.hud(h * 0.085))
                    .foregroundStyle(theme.label.color),
                   at: CGPoint(x: cx, y: y1 + h * 0.11), anchor: .center)
    }
}
