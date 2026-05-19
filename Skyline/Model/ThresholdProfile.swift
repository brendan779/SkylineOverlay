import Foundation

/// One colour stop in a threshold profile — a metric value paired with the
/// colour the widget should take at that value.
struct ThresholdStop: Codable, Equatable, Identifiable {
    var id: UUID
    var value: Double
    var color: RGBAColor

    init(value: Double, color: RGBAColor, id: UUID = UUID()) {
        self.id = id
        self.value = value
        self.color = color
    }
}

/// Per-widget threshold colouring: a set of value→colour stops the widget
/// interpolates against at runtime. Persisted with the widget in a layout.
struct ThresholdProfile: Codable, Equatable {
    var isEnabled: Bool
    var stops: [ThresholdStop]

    init(isEnabled: Bool = false, stops: [ThresholdStop] = []) {
        self.isEnabled = isEnabled
        self.stops = stops
    }

    static let disabled = ThresholdProfile()

    /// The colour for `value`, interpolated between the bounding stops, or
    /// `nil` when the profile is off or empty (the widget keeps its accent).
    func color(for value: Double) -> RGBAColor? {
        guard isEnabled else { return nil }
        let sorted = stops.sorted { $0.value < $1.value }
        guard let first = sorted.first, let last = sorted.last else { return nil }
        if value <= first.value { return first.color }
        if value >= last.value { return last.color }
        for i in 1..<sorted.count {
            let lo = sorted[i - 1], hi = sorted[i]
            if value <= hi.value {
                let span = hi.value - lo.value
                let f = span > 0 ? (value - lo.value) / span : 0
                return lo.color.lerp(to: hi.color, f)
            }
        }
        return last.color
    }
}

// ── Common colours + presets ─────────────────────────────────────────────

extension RGBAColor {
    static let zoneGreen  = RGBAColor(0.30, 0.80, 0.38)
    static let zoneYellow = RGBAColor(0.95, 0.78, 0.22)
    static let zoneRed    = RGBAColor(0.92, 0.30, 0.24)
}

extension ThresholdProfile {
    /// Named starting points the threshold editor can drop in. The first
    /// entry of every list is a sensible default for that widget kind.
    static func presets(for kind: WidgetKind) -> [(name: String, profile: ThresholdProfile)] {
        func profile(_ pairs: [(Double, RGBAColor)]) -> ThresholdProfile {
            ThresholdProfile(isEnabled: true,
                             stops: pairs.map { ThresholdStop(value: $0.0, color: $0.1) })
        }
        switch kind {
        case .battery:
            return [
                ("LiPo 3S", profile([(10.5, .zoneRed), (11.1, .zoneYellow),
                                     (12.6, .zoneGreen)])),
                ("LiPo 4S", profile([(14.0, .zoneRed), (14.8, .zoneYellow),
                                     (16.8, .zoneGreen)])),
                ("LiPo 6S", profile([(21.0, .zoneRed), (22.2, .zoneYellow),
                                     (25.2, .zoneGreen)])),
            ]
        case .gforce:
            return [
                ("Light → Hard", profile([(0, .zoneGreen), (2, .zoneYellow),
                                          (4, .zoneRed)])),
            ]
        case .altitude:
            return [
                ("AGL ceiling", profile([(0, .zoneGreen), (100, .zoneYellow),
                                         (120, .zoneRed)])),
            ]
        case .groundSpeed, .airSpeed:
            return [
                ("Slow → Fast", profile([(0, .zoneGreen), (60, .zoneYellow),
                                         (90, .zoneRed)])),
            ]
        default:
            return []
        }
    }
}
