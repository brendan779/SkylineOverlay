import SwiftUI

/// Top-down stylised view of a quadplane's lift rotors, with each motor's
/// current RPM drawn inside its prop disc. Supports the two layouts that
/// matter in practice for the user's airframes: **tri-Y** (3 lift motors)
/// and **Quad X** (4 lift motors). Anything else renders a "not supported
/// for this airframe" placeholder.
///
/// Motor instance numbering follows ArduPilot's standard:
/// - **Quad X**: M1 front-right, M2 rear-left, M3 front-left, M4 rear-right.
/// - **Tri-Y**:  M1 front-right, M2 front-left, M3 rear-centre.
struct ESCRPMWidget: View {
    var settings: WidgetSettings
    var theme: OverlayTheme
    var motors: [TelemetrySample.ESCMotor]
    var maxRPM: Double
    var hasESC: Bool
    var size: CGSize

    var body: some View {
        Canvas { ctx, sz in draw(&ctx, sz) }
            .frame(width: size.width, height: size.height)
    }

    private func draw(_ ctx: inout GraphicsContext, _ sz: CGSize) {
        let w = sz.width, h = sz.height
        let panel = Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h),
                         cornerRadius: min(w, h) * 0.08)
        ctx.fill(panel, with: .color(settings.background.color))
        ctx.stroke(panel, with: .color(.white.opacity(0.22)), lineWidth: 1)

        ctx.draw(Text("ESC RPM").font(.hud(h * 0.055))
                    .foregroundStyle(theme.label.color),
                 at: CGPoint(x: w / 2, y: h * 0.07), anchor: .center)

        // Placeholder when there's no useful data to draw.
        guard hasESC else {
            ctx.draw(Text("NO ESC DATA").font(.hud(h * 0.065))
                        .foregroundStyle(theme.label.color),
                     at: CGPoint(x: w / 2, y: h / 2), anchor: .center)
            return
        }
        guard motors.count == 3 || motors.count == 4 else {
            ctx.draw(Text("ESC RPM widget supports").font(.hud(h * 0.05))
                        .foregroundStyle(theme.label.color),
                     at: CGPoint(x: w / 2, y: h * 0.46), anchor: .center)
            ctx.draw(Text("tri-Y and Quad X airframes only")
                        .font(.hud(h * 0.05))
                        .foregroundStyle(theme.label.color),
                     at: CGPoint(x: w / 2, y: h * 0.54), anchor: .center)
            return
        }

        let centre = CGPoint(x: w / 2, y: h / 2 + h * 0.02)
        drawPlane(&ctx, at: centre, size: sz)

        let positions = motorPositions(centre: centre, size: sz,
                                       count: motors.count)
        let motorRadius = w * 0.13

        // Render motors in instance order, looking up each instance's
        // position from the layout table.
        for motor in motors {
            guard let position = positions[motor.instance + 1] else { continue }
            drawMotor(&ctx, motor: motor, at: position, radius: motorRadius,
                      panelHeight: h)
        }
    }

    /// Light fuselage + wing silhouette, centred on the canvas. Drawn at
    /// low contrast so the motor numbers dominate.
    private func drawPlane(_ ctx: inout GraphicsContext, at c: CGPoint,
                           size sz: CGSize) {
        let w = sz.width, h = sz.height
        let bodyColour = theme.label.color.opacity(0.32)

        // Fuselage — a tall thin rounded rect from nose (top) to tail.
        let fuselageW = w * 0.05
        let fuselageH = h * 0.42
        let fuselage = Path(roundedRect:
            CGRect(x: c.x - fuselageW / 2, y: c.y - fuselageH / 2,
                   width: fuselageW, height: fuselageH),
            cornerRadius: fuselageW / 2)
        ctx.fill(fuselage, with: .color(bodyColour))

        // Nose dot for orientation.
        let noseR = w * 0.018
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - noseR,
                                        y: c.y - fuselageH / 2 - noseR * 0.4,
                                        width: noseR * 2, height: noseR * 2)),
                 with: .color(theme.label.color.opacity(0.55)))

        // Wing — horizontal bar at mid-fuselage.
        let wingW = w * 0.22
        let wingH = h * 0.04
        let wing = Path(roundedRect:
            CGRect(x: c.x - wingW / 2, y: c.y - wingH / 2,
                   width: wingW, height: wingH),
            cornerRadius: wingH / 2)
        ctx.fill(wing, with: .color(bodyColour))

        // Tail — smaller horizontal bar near the back of the fuselage.
        let tailW = w * 0.10
        let tailH = h * 0.025
        let tail = Path(roundedRect:
            CGRect(x: c.x - tailW / 2, y: c.y + fuselageH / 2 - tailH,
                   width: tailW, height: tailH),
            cornerRadius: tailH / 2)
        ctx.fill(tail, with: .color(bodyColour))
    }

    /// Position the motor centres for the given count, keyed by motor
    /// number (1-based). ArduPilot conventions:
    /// - Quad X: M1 front-right, M2 rear-left, M3 front-left, M4 rear-right.
    /// - Tri-Y:  M1 front-right, M2 front-left, M3 rear-centre.
    private func motorPositions(centre c: CGPoint, size sz: CGSize,
                                count: Int) -> [Int: CGPoint] {
        let w = sz.width, h = sz.height
        switch count {
        case 4:
            let dx = w * 0.30
            let dy = h * 0.32
            return [
                1: CGPoint(x: c.x + dx, y: c.y - dy),   // front-right
                2: CGPoint(x: c.x - dx, y: c.y + dy),   // rear-left
                3: CGPoint(x: c.x - dx, y: c.y - dy),   // front-left
                4: CGPoint(x: c.x + dx, y: c.y + dy),   // rear-right
            ]
        case 3:
            let dx = w * 0.30
            let dy = h * 0.30
            return [
                1: CGPoint(x: c.x + dx, y: c.y - dy),   // front-right
                2: CGPoint(x: c.x - dx, y: c.y - dy),   // front-left
                3: CGPoint(x: c.x, y: c.y + dy),        // rear-centre
            ]
        default:
            return [:]
        }
    }

    /// One motor's prop disc, ring gauge and RPM readout.
    private func drawMotor(_ ctx: inout GraphicsContext,
                           motor: TelemetrySample.ESCMotor,
                           at p: CGPoint, radius r: CGFloat,
                           panelHeight h: CGFloat) {
        var layer = ctx
        layer.opacity = motor.opacity

        let accent = settings.accent.color
        let dim = theme.label.color.opacity(0.35)

        // Prop disc backdrop.
        let disc = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
        layer.fill(Path(ellipseIn: disc),
                   with: .color(.black.opacity(0.45)))

        // Ring gauge — accent-coloured arc on the outer rim. Fraction of
        // the dynamic max RPM determined at log-load.
        let fraction = maxRPM > 0
            ? max(0.0, min(1.0, motor.rpm / maxRPM))
            : 0
        let ringWidth = r * 0.18
        let arcRect = disc.insetBy(dx: ringWidth / 2, dy: ringWidth / 2)
        // Background track.
        layer.stroke(Path(ellipseIn: arcRect),
                     with: .color(dim), lineWidth: ringWidth)
        // Foreground arc — sweep from the top (-90°) clockwise.
        if fraction > 0 {
            var arc = Path()
            arc.addArc(center: p, radius: r - ringWidth / 2,
                       startAngle: .degrees(-90),
                       endAngle: .degrees(-90 + 360 * fraction),
                       clockwise: false)
            layer.stroke(arc, with: .color(accent),
                         style: StrokeStyle(lineWidth: ringWidth,
                                            lineCap: .round))
        }

        // RPM number — large, centred.
        let rpmStr = String(Int(motor.rpm.rounded()))
        layer.draw(Text(rpmStr).font(.hud(h * 0.075, weight: .semibold))
                    .foregroundStyle(.white),
                   at: p, anchor: .center)

        // Tiny instance label outside the disc, near the airframe centre.
        let labelOffsetX = (p.x < disc.midX) ? r + 4 : -r - 4
        let labelAnchor: UnitPoint = (p.x < disc.midX) ? .leading : .trailing
        layer.draw(Text("M\(motor.instance + 1)").font(.hud(h * 0.045))
                    .foregroundStyle(theme.label.color.opacity(0.65)),
                   at: CGPoint(x: p.x + labelOffsetX, y: p.y + r),
                   anchor: labelAnchor)
    }
}
