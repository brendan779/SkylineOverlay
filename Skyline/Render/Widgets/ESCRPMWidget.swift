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
        let positions = motorPositions(centre: centre, size: sz,
                                       count: motors.count)
        let motorRadius = w * 0.13

        // Arms and centre body first so the motor discs draw on top —
        // the arms appear to terminate cleanly inside each prop disc.
        drawAirframe(&ctx, centre: centre, positions: positions,
                     motorRadius: motorRadius, motorCount: motors.count,
                     size: sz)

        // The motor *number* comes from the position in the sorted ESC
        // list, not from the raw Instance value — ArduPilot's ESC
        // Instance is the servo channel index (so lift motors on C7–C10
        // log as instances 6–9, etc.), which would never match the 1–N
        // motor mapping otherwise.
        for (index, motor) in motors.enumerated() {
            let motorNumber = index + 1
            guard let position = positions[motorNumber] else { continue }
            drawMotor(&ctx, motor: motor, motorNumber: motorNumber,
                      at: position, radius: motorRadius, panelHeight: h)
        }
    }

    /// Skyline-style adaptation of ArduPilot's motor-layout diagrams —
    /// arms radiating from a central FC body to each motor position,
    /// plus a tail-servo cue under M3 for tri-Y. Drawn dim so the motor
    /// numbers dominate the widget visually.
    private func drawAirframe(_ ctx: inout GraphicsContext,
                              centre c: CGPoint,
                              positions: [Int: CGPoint],
                              motorRadius mr: CGFloat,
                              motorCount: Int,
                              size sz: CGSize) {
        let w = sz.width, h = sz.height
        let arm = theme.label.color.opacity(0.45)
        let body = theme.label.color.opacity(0.65)
        let armWidth = max(2, h * 0.014)

        // Arms — line from centre to just inside the disc edge.
        for p in positions.values {
            let dx = p.x - c.x
            let dy = p.y - c.y
            let length = sqrt(dx * dx + dy * dy)
            guard length > 0 else { continue }
            let stop = max(0, length - mr * 0.95)
            let end = CGPoint(x: c.x + dx * stop / length,
                              y: c.y + dy * stop / length)
            var line = Path()
            line.move(to: c)
            line.addLine(to: end)
            ctx.stroke(line, with: .color(arm),
                       style: StrokeStyle(lineWidth: armWidth,
                                          lineCap: .round))
        }

        // Tail‑servo cue on the rear motor for tri-Y — a small filled
        // rectangle just outside the rear disc, ArduPilot-style.
        if motorCount == 3, let rear = positions[3] {
            let servoW = w * 0.045
            let servoH = h * 0.035
            let rect = CGRect(
                x: rear.x - servoW / 2,
                y: rear.y + mr + servoH * 0.4,
                width: servoW, height: servoH)
            ctx.fill(Path(roundedRect: rect, cornerRadius: servoH * 0.2),
                     with: .color(arm))
            // Thin tail‑rotor axis hint into the disc.
            var stem = Path()
            stem.move(to: CGPoint(x: rear.x, y: rect.minY))
            stem.addLine(to: CGPoint(x: rear.x, y: rear.y + mr))
            ctx.stroke(stem, with: .color(arm),
                       style: StrokeStyle(lineWidth: max(1, armWidth * 0.5),
                                          lineCap: .round))
        }

        // Central FC body — small rounded square covering the arm
        // crossings, with an upward chevron marking the nose direction.
        let bodyW = w * 0.085
        let bodyR = bodyW * 0.30
        let bodyRect = CGRect(x: c.x - bodyW / 2, y: c.y - bodyW / 2,
                              width: bodyW, height: bodyW)
        ctx.fill(Path(roundedRect: bodyRect, cornerRadius: bodyR),
                 with: .color(theme.label.color.opacity(0.18)))
        ctx.stroke(Path(roundedRect: bodyRect, cornerRadius: bodyR),
                   with: .color(arm), lineWidth: 1)

        let chW = bodyW * 0.42
        let chH = bodyW * 0.32
        var chevron = Path()
        chevron.move(to: CGPoint(x: c.x - chW / 2, y: c.y + chH / 2))
        chevron.addLine(to: CGPoint(x: c.x, y: c.y - chH / 2))
        chevron.addLine(to: CGPoint(x: c.x + chW / 2, y: c.y + chH / 2))
        ctx.stroke(chevron, with: .color(body),
                   style: StrokeStyle(lineWidth: max(1.5, armWidth * 0.85),
                                      lineCap: .round, lineJoin: .round))
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
                           motorNumber: Int,
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

        // Motor number label outside the disc. Position-derived so it
        // matches the ArduPilot Quad X / tri-Y convention regardless of
        // what raw Instance values the log carries.
        let labelOffsetX = (p.x < disc.midX) ? r + 4 : -r - 4
        let labelAnchor: UnitPoint = (p.x < disc.midX) ? .leading : .trailing
        layer.draw(Text("M\(motorNumber)").font(.hud(h * 0.045))
                    .foregroundStyle(theme.label.color.opacity(0.65)),
                   at: CGPoint(x: p.x + labelOffsetX, y: p.y + r),
                   anchor: labelAnchor)
    }
}
