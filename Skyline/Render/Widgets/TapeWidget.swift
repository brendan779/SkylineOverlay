import SwiftUI

/// Vertical tape widget — used for ground speed, airspeed and altitude.
///
/// A scrolling tick rail centred on the current value, with a readout box
/// (accent edge + pointer) showing the precise figure.
struct TapeWidget: View {
    var settings: WidgetSettings
    var theme: OverlayTheme
    var value: Double
    var unit: String
    var label: String
    var size: CGSize

    /// Value range spanned by the visible rail.
    private let span = 60.0
    private let majorStep = 10.0
    private let minorStep = 2.0

    var body: some View {
        Canvas { ctx, sz in draw(&ctx, sz) }
            .frame(width: size.width, height: size.height)
    }

    private func draw(_ ctx: inout GraphicsContext, _ sz: CGSize) {
        let w = sz.width
        let h = sz.height
        let accent = settings.accent.color

        // Panel
        let panel = Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h),
                         cornerRadius: h * 0.12)
        ctx.fill(panel, with: .color(settings.background.color))
        ctx.stroke(panel, with: .color(.white.opacity(0.22)), lineWidth: 1)

        // Label
        ctx.draw(Text(label).font(condensed(h * 0.11)).foregroundStyle(theme.label.color),
                 at: CGPoint(x: w / 2, y: h * 0.09), anchor: .center)

        // Tick rail
        let railTop = h * 0.18
        let railBottom = h * 0.96
        let railH = railBottom - railTop
        let railX = w * 0.34
        ctx.stroke(line(railX, railTop, railX, railBottom),
                   with: .color(.white.opacity(0.15)), lineWidth: 1)

        let pxPerUnit = railH / span
        var v = ((value - span / 2 - majorStep) / minorStep).rounded(.down) * minorStep
        while v <= value + span / 2 + majorStep {
            let y = railTop + railH / 2 - CGFloat(v - value) * pxPerUnit
            if y >= railTop - 2, y <= railBottom + 2 {
                let isMajor = Int(v.rounded()).isMultiple(of: Int(majorStep))
                let len: CGFloat = isMajor ? w * 0.12 : w * 0.06
                ctx.stroke(line(railX, y, railX + len, y),
                           with: .color(.white.opacity(isMajor ? 0.6 : 0.32)),
                           lineWidth: 1)
                if isMajor {
                    ctx.draw(Text("\(Int(v.rounded()))")
                                .font(condensed(h * 0.085))
                                .foregroundStyle(.white.opacity(0.65)),
                             at: CGPoint(x: railX - w * 0.05, y: y),
                             anchor: .trailing)
                }
            }
            v += minorStep
        }

        // Readout box
        let boxW = w * 0.52
        let boxH = h * 0.32
        let boxX = w - boxW - w * 0.05
        let boxY = railTop + railH / 2 - boxH / 2
        let midY = boxY + boxH / 2
        let box = Path(roundedRect: CGRect(x: boxX, y: boxY, width: boxW, height: boxH),
                       cornerRadius: 4)
        ctx.fill(box, with: .color(.black.opacity(0.72)))
        ctx.fill(Path(CGRect(x: boxX, y: boxY,
                             width: max(2, w * 0.025), height: boxH)),
                 with: .color(accent))

        // Pointer triangle toward the rail
        let ptr = w * 0.06
        var tri = Path()
        tri.move(to: CGPoint(x: boxX, y: midY - ptr))
        tri.addLine(to: CGPoint(x: boxX, y: midY + ptr))
        tri.addLine(to: CGPoint(x: boxX - ptr, y: midY))
        tri.closeSubpath()
        ctx.fill(tri, with: .color(.white.opacity(0.32)))

        // Value + unit
        ctx.draw(Text(String(format: "%.0f", value))
                    .font(condensed(h * 0.21, weight: .semibold))
                    .foregroundStyle(.white),
                 at: CGPoint(x: boxX + boxW / 2, y: midY - boxH * 0.10),
                 anchor: .center)
        ctx.draw(Text(unit).font(condensed(h * 0.085))
                    .foregroundStyle(theme.label.color),
                 at: CGPoint(x: boxX + boxW / 2, y: midY + boxH * 0.28),
                 anchor: .center)
    }

    private func line(_ x0: CGFloat, _ y0: CGFloat,
                      _ x1: CGFloat, _ y1: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: x0, y: y0))
        p.addLine(to: CGPoint(x: x1, y: y1))
        return p
    }

    private func condensed(_ size: CGFloat,
                           weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }
}
