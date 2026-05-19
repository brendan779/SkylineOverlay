import SwiftUI

/// Battery state — a horizontal fuel gauge with green / yellow / red zones,
/// plus numeric readouts for voltage, current and charge drawn.
///
/// The remaining percentage is `consumed` measured against the pack capacity
/// the user sets in the Inspector.
struct BatteryWidget: View {
    var settings: WidgetSettings
    var theme: OverlayTheme
    var voltage: Double         // V
    var current: Double         // A
    var consumed: Double        // mAh drawn
    var capacity: Double        // mAh pack baseline
    var hasData: Bool
    /// Threshold colour for the current voltage; overrides the % zone colour.
    var thresholdColor: Color? = nil
    var size: CGSize

    /// Fraction of the pack still available, 0…1, or nil when no baseline.
    private var remaining: Double? {
        guard capacity > 0 else { return nil }
        return max(0, min(1, 1 - consumed / capacity))
    }

    /// Gauge colour: the threshold colour when set, otherwise the green /
    /// yellow / red zone for the remaining fraction.
    private func zoneColor(_ fraction: Double) -> Color {
        if let thresholdColor { return thresholdColor }
        if fraction > 0.5 { return Color(red: 0.30, green: 0.80, blue: 0.38) }
        if fraction > 0.2 { return Color(red: 0.95, green: 0.78, blue: 0.22) }
        return Color(red: 0.92, green: 0.30, blue: 0.24)
    }

    var body: some View {
        Canvas { ctx, sz in draw(&ctx, sz) }
            .frame(width: size.width, height: size.height)
    }

    private func draw(_ ctx: inout GraphicsContext, _ sz: CGSize) {
        let w = sz.width, h = sz.height

        // Panel
        let panel = Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h),
                         cornerRadius: h * 0.16)
        ctx.fill(panel, with: .color(settings.background.color))
        ctx.stroke(panel, with: .color(.white.opacity(0.22)), lineWidth: 1)

        // Label + percentage
        ctx.draw(Text("BATTERY").font(.hud(h * 0.135))
                    .foregroundStyle(theme.label.color),
                 at: CGPoint(x: w * 0.09, y: h * 0.16), anchor: .leading)
        if let remaining {
            ctx.draw(Text("\(Int((remaining * 100).rounded()))%")
                        .font(.hud(h * 0.155, weight: .semibold))
                        .foregroundStyle(zoneColor(remaining)),
                     at: CGPoint(x: w * 0.91, y: h * 0.16), anchor: .trailing)
        }

        // Gauge body
        let barX = w * 0.09
        let barY = h * 0.30
        let barH = h * 0.24
        let capW = w * 0.025
        let barW = w * 0.82 - capW - 3
        let trough = Path(roundedRect: CGRect(x: barX, y: barY,
                                              width: barW, height: barH),
                          cornerRadius: barH * 0.25)
        ctx.fill(trough, with: .color(.black.opacity(0.55)))

        if let remaining, hasData {
            let fillW = max(barH * 0.5, barW * remaining)
            let fill = Path(roundedRect: CGRect(x: barX, y: barY,
                                                width: fillW, height: barH),
                            cornerRadius: barH * 0.25)
            ctx.fill(fill, with: .color(zoneColor(remaining)))
        }
        ctx.stroke(trough, with: .color(.white.opacity(0.30)), lineWidth: 1)

        // Cap nub on the right
        let nub = Path(roundedRect: CGRect(x: barX + barW + 3,
                                           y: barY + barH * 0.28,
                                           width: capW, height: barH * 0.44),
                       cornerRadius: capW * 0.4)
        ctx.fill(nub, with: .color(.white.opacity(0.30)))

        // Numeric readouts
        let readoutY = h * 0.70
        readout(&ctx, value: hasData ? String(format: "%.1f", voltage) : "—",
                unit: "V", at: CGPoint(x: w * 0.21, y: readoutY), h: h)
        readout(&ctx, value: hasData ? String(format: "%.1f", current) : "—",
                unit: "A", at: CGPoint(x: w * 0.50, y: readoutY), h: h)
        readout(&ctx, value: hasData ? String(format: "%.0f", consumed) : "—",
                unit: "mAh", at: CGPoint(x: w * 0.80, y: readoutY), h: h)
    }

    /// One centred value-over-unit readout column.
    private func readout(_ ctx: inout GraphicsContext, value: String,
                         unit: String, at p: CGPoint, h: CGFloat) {
        ctx.draw(Text(value).font(.hud(h * 0.21, weight: .semibold))
                    .foregroundStyle(.white),
                 at: CGPoint(x: p.x, y: p.y), anchor: .center)
        ctx.draw(Text(unit).font(.hud(h * 0.115))
                    .foregroundStyle(theme.label.color),
                 at: CGPoint(x: p.x, y: p.y + h * 0.150), anchor: .center)
    }
}
