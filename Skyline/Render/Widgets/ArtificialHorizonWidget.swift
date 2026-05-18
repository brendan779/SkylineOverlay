import SwiftUI

/// Artificial horizon — rotating sky/ground split, pitch ladder, a fixed
/// roll arc with a moving pointer, and the fixed aircraft reticle.
struct ArtificialHorizonWidget: View {
    var settings: WidgetSettings
    var theme: OverlayTheme
    var pitch: Double
    var roll: Double
    var size: CGSize

    private let sky = Color(.sRGB, red: 0.176, green: 0.392, blue: 0.647, opacity: 0.88)
    private let ground = Color(.sRGB, red: 0.372, green: 0.243, blue: 0.086, opacity: 0.88)

    var body: some View {
        Canvas { ctx, sz in draw(&ctx, sz) }
            .frame(width: size.width, height: size.height)
    }

    private func draw(_ ctx: inout GraphicsContext, _ sz: CGSize) {
        let w = sz.width, h = sz.height
        let cx = w / 2, cy = h / 2
        let pxPerDeg = h / 55.0
        let accent = settings.accent.color
        let panel = Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h),
                         cornerRadius: h * 0.12)

        // Sky / ground + pitch ladder live in a clipped, rotated layer.
        var world = ctx
        world.clip(to: panel)
        world.translateBy(x: cx, y: cy)
        world.rotate(by: .degrees(roll))

        let big = max(w, h) * 2.4
        let horizon = CGFloat(pitch) * pxPerDeg
        world.fill(Path(CGRect(x: -big, y: -big, width: 2 * big, height: big + horizon)),
                   with: .color(sky))
        world.fill(Path(CGRect(x: -big, y: horizon, width: 2 * big, height: 2 * big)),
                   with: .color(ground))
        world.stroke(segment(-big, horizon, big, horizon),
                     with: .color(.white.opacity(0.7)), lineWidth: 2)

        for a in stride(from: -20, through: 20, by: 10) where a != 0 {
            let y = CGFloat(pitch - Double(a)) * pxPerDeg
            let half: CGFloat = abs(a) == 20 ? w * 0.15 : w * 0.10
            world.stroke(segment(-half, y, half, y),
                         with: .color(.white.opacity(0.45)), lineWidth: 1)
            let label = Text("\(abs(a))").font(.hud(h * 0.085))
                .foregroundStyle(.white.opacity(0.6))
            world.draw(label, at: CGPoint(x: half + w * 0.035, y: y), anchor: .leading)
            world.draw(label, at: CGPoint(x: -half - w * 0.035, y: y), anchor: .trailing)
        }

        // Roll arc + pointer (fixed frame).
        let arcCx = cx, arcCy = cy + h * 0.34
        let arcR = h * 0.66
        var arc = Path()
        arc.addArc(center: CGPoint(x: arcCx, y: arcCy), radius: arcR,
                   startAngle: .degrees(-150), endAngle: .degrees(-30),
                   clockwise: false)
        ctx.stroke(arc, with: .color(.white.opacity(0.5)), lineWidth: 1)
        for tick in stride(from: -60, through: 60, by: 30) {
            let ang = Double(-90 + tick) * .pi / 180
            let r1 = arcR - (tick == 0 ? h * 0.07 : h * 0.045)
            ctx.stroke(segment(arcCx + CGFloat(cos(ang)) * arcR,
                               arcCy + CGFloat(sin(ang)) * arcR,
                               arcCx + CGFloat(cos(ang)) * r1,
                               arcCy + CGFloat(sin(ang)) * r1),
                       with: .color(.white.opacity(0.6)), lineWidth: 1)
        }
        let pAng = (Double(-90) + roll) * .pi / 180
        let px = arcCx + CGFloat(cos(pAng)) * (arcR - h * 0.02)
        let py = arcCy + CGFloat(sin(pAng)) * (arcR - h * 0.02)
        let psz = h * 0.055
        var ptr = Path()
        ptr.move(to: CGPoint(x: px, y: py))
        ptr.addLine(to: CGPoint(x: px - psz * CGFloat(cos(pAng - 0.45)),
                                y: py - psz * CGFloat(sin(pAng - 0.45))))
        ptr.addLine(to: CGPoint(x: px - psz * CGFloat(cos(pAng + 0.45)),
                                y: py - psz * CGFloat(sin(pAng + 0.45))))
        ptr.closeSubpath()
        ctx.fill(ptr, with: .color(accent))

        // Fixed aircraft reticle.
        let arm = w * 0.16
        let dot: CGFloat = max(2, h * 0.018)
        ctx.stroke(segment(cx - arm, cy, cx - dot * 2, cy),
                   with: .color(.white), lineWidth: 2)
        ctx.stroke(segment(cx + dot * 2, cy, cx + arm, cy),
                   with: .color(.white), lineWidth: 2)
        ctx.fill(Path(ellipseIn: CGRect(x: cx - dot, y: cy - dot,
                                        width: 2 * dot, height: 2 * dot)),
                 with: .color(.white))

        ctx.draw(Text("ATT").font(.hud(h * 0.10))
                    .foregroundStyle(theme.label.color),
                 at: CGPoint(x: cx, y: h * 0.09), anchor: .center)
        ctx.stroke(panel, with: .color(.white.opacity(0.22)), lineWidth: 1)
    }
}
