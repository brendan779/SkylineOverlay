import SwiftUI
import Observation

// ── Global enums ─────────────────────────────────────────────────────────

enum SpeedUnit: String, CaseIterable, Codable, Identifiable {
    case kmh, mph, ms
    var id: String { rawValue }

    var label: String {
        switch self {
        case .kmh: return "km/h"
        case .mph: return "mph"
        case .ms:  return "m/s"
        }
    }

    /// Convert a value in metres/second to this unit.
    func convert(_ metresPerSecond: Double) -> Double {
        switch self {
        case .kmh: return metresPerSecond * 3.6
        case .mph: return metresPerSecond * 2.236936
        case .ms:  return metresPerSecond
        }
    }
}

enum DistanceUnit: String, CaseIterable, Codable, Identifiable {
    case meters, feet
    var id: String { rawValue }

    var label: String { self == .meters ? "m" : "ft" }

    /// Convert a value in metres to this unit.
    func convert(_ metres: Double) -> Double {
        self == .meters ? metres : metres * 3.280839895
    }
}

/// Per-widget smoothing of the channel it displays.
struct SmoothingSettings: Codable, Equatable {
    /// Moving-average window in seconds; 0 disables smoothing.
    var window: Double
    /// Use the precomputed Kalman-filtered channel instead of the average.
    var useKalman: Bool

    init(window: Double = 0, useKalman: Bool = false) {
        self.window = window
        self.useKalman = useKalman
    }

    static let off = SmoothingSettings()

    /// Whether this widget should draw a smoothed value at all.
    var isActive: Bool { useKalman || window > 0 }
}

enum FlightMapStyle: String, CaseIterable, Codable, Identifiable {
    case standard, satellite, hybrid
    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard:  return "Standard"
        case .satellite: return "Satellite"
        case .hybrid:    return "Hybrid"
        }
    }
}

enum AltitudeDatum: String, CaseIterable, Codable, Identifiable {
    case relative, absolute
    var id: String { rawValue }
    var label: String { self == .relative ? "Relative (AGL)" : "Absolute (AMSL)" }
}

enum VideoCodec: String, CaseIterable, Codable, Identifiable {
    case proRes4444     // ProRes 4444 — real alpha channel
    case proRes422HQ    // ProRes 422 HQ — no alpha
    case h264
    var id: String { rawValue }

    var label: String {
        switch self {
        case .proRes4444:  return "ProRes 4444 (alpha)"
        case .proRes422HQ: return "ProRes 422 HQ"
        case .h264:        return "H.264"
        }
    }

    var supportsAlpha: Bool { self == .proRes4444 }
}

// ── Output settings ──────────────────────────────────────────────────────

struct OutputSettings: Codable, Equatable {
    var width: Int
    var height: Int
    var fps: Double
    var codec: VideoCodec
    var transparent: Bool

    static let `default` = OutputSettings(
        width: 1920, height: 1080, fps: 30, codec: .proRes4444, transparent: true)
}

// ── Theme ────────────────────────────────────────────────────────────────

/// Global colour palette + typography. Per-widget colour overrides live on
/// `WidgetSettings`; a widget defaults to the theme's accent/background.
struct OverlayTheme: Codable, Equatable {
    var accent: RGBAColor
    var background: RGBAColor
    var label: RGBAColor
    var value: RGBAColor
    var message: RGBAColor
    var warning: RGBAColor
    var fontName: String

    static let `default` = OverlayTheme(
        accent:     RGBAColor(0.69, 0.44, 0.63, 1.0),   // mauve
        background: RGBAColor(0.05, 0.05, 0.05, 0.85),
        label:      RGBAColor(0.65, 0.65, 0.65, 1.0),
        value:      RGBAColor(1.0, 1.0, 1.0, 1.0),
        message:    RGBAColor(1.0, 0.85, 0.35, 1.0),
        warning:    RGBAColor(1.0, 0.40, 0.10, 1.0),
        fontName:   "Barlow Condensed")
}

// ── Per-widget settings ──────────────────────────────────────────────────

/// Tunable properties common to every widget. The Inspector edits these;
/// both the live preview and the video exporter read them.
struct WidgetSettings: Codable, Equatable {
    var isEnabled: Bool
    var position: CGPoint      // normalised 0...1 — the widget's centre
    var scale: Double          // size multiplier
    var opacity: Double        // 0...1
    var accent: RGBAColor      // per-widget accent
    var background: RGBAColor  // per-widget panel background

    static let scaleRange: ClosedRange<Double> = 0.4...2.5

    static func `default`(for kind: WidgetKind, theme: OverlayTheme) -> WidgetSettings {
        WidgetSettings(
            isEnabled: true,
            position: defaultPosition(for: kind),
            scale: 1.0,
            opacity: 1.0,
            accent: theme.accent,
            background: theme.background)
    }

    /// Default placements reproduce the renderer's lower-third layout: an
    /// evenly spread main band, the rangefinder tucked into the gap below it,
    /// and the flight mode / messages stacked at the top right.
    private static func defaultPosition(for kind: WidgetKind) -> CGPoint {
        switch kind {
        case .groundSpeed:   return CGPoint(x: 0.055, y: 0.84)
        case .airSpeed:      return CGPoint(x: 0.125, y: 0.84)
        case .wind:          return CGPoint(x: 0.205, y: 0.84)
        case .altitude:      return CGPoint(x: 0.305, y: 0.84)
        case .rangefinder:   return CGPoint(x: 0.390, y: 0.90)
        case .battery:       return CGPoint(x: 0.085, y: 0.075)
        case .gforce:        return CGPoint(x: 0.870, y: 0.30)
        case .distance:      return CGPoint(x: 0.090, y: 0.20)
        case .map:           return CGPoint(x: 0.160, y: 0.58)
        case .attitude:      return CGPoint(x: 0.500, y: 0.83)
        case .heading:       return CGPoint(x: 0.500, y: 0.93)
        case .verticalSpeed: return CGPoint(x: 0.620, y: 0.84)
        case .motors:        return CGPoint(x: 0.725, y: 0.84)
        case .flightMode:    return CGPoint(x: 0.930, y: 0.74)
        case .messages:      return CGPoint(x: 0.905, y: 0.83)
        }
    }
}

// ── Overlay configuration ────────────────────────────────────────────────

/// The single observable model the Inspector edits and the renderer reads.
/// One instance is held per flight session.
@Observable
final class OverlayConfig {
    var theme: OverlayTheme
    var speedUnits: SpeedUnit
    var altitudeDatum: AltitudeDatum
    var output: OutputSettings
    var messageDisplaySeconds: Double
    /// Pack capacity in mAh — the baseline the Battery widget uses to turn
    /// consumed charge into a remaining percentage.
    var batteryCapacity: Double
    /// Full-scale deflection of the G-Force meter, in g (±value).
    var gForceScale: Double
    /// Unit the Distance from Home widget displays in.
    var distanceUnits: DistanceUnit
    /// Whether the Distance from Home widget shows a max-reached sub-label.
    var showMaxDistance: Bool
    /// GPS Map tile style.
    var mapStyle: FlightMapStyle
    /// Map zoom: 1 auto-fits the flight bounds, higher zooms in.
    var mapZoom: Double
    /// Trail length in seconds; 0 draws the full flight path.
    var mapTrailSeconds: Double
    var widgets: [WidgetKind: WidgetSettings]
    /// Per-widget threshold colour profiles.
    var thresholds: [WidgetKind: ThresholdProfile]
    /// Per-widget channel smoothing.
    var smoothing: [WidgetKind: SmoothingSettings]

    init(theme: OverlayTheme = .default,
         speedUnits: SpeedUnit = .kmh,
         altitudeDatum: AltitudeDatum = .relative,
         output: OutputSettings = .default,
         messageDisplaySeconds: Double = 4.0,
         batteryCapacity: Double = 5000,
         gForceScale: Double = 2,
         distanceUnits: DistanceUnit = .meters,
         showMaxDistance: Bool = true,
         mapStyle: FlightMapStyle = .standard,
         mapZoom: Double = 1,
         mapTrailSeconds: Double = 0,
         widgets: [WidgetKind: WidgetSettings]? = nil,
         thresholds: [WidgetKind: ThresholdProfile] = [:],
         smoothing: [WidgetKind: SmoothingSettings] = [:]) {
        self.theme = theme
        self.speedUnits = speedUnits
        self.altitudeDatum = altitudeDatum
        self.output = output
        self.messageDisplaySeconds = messageDisplaySeconds
        self.batteryCapacity = batteryCapacity
        self.gForceScale = gForceScale
        self.distanceUnits = distanceUnits
        self.showMaxDistance = showMaxDistance
        self.mapStyle = mapStyle
        self.mapZoom = mapZoom
        self.mapTrailSeconds = mapTrailSeconds
        self.thresholds = thresholds
        self.smoothing = smoothing
        if let widgets {
            self.widgets = widgets
        } else {
            var defaults: [WidgetKind: WidgetSettings] = [:]
            for kind in WidgetKind.allCases {
                defaults[kind] = .default(for: kind, theme: theme)
            }
            self.widgets = defaults
        }
    }

    /// Non-optional access — falls back to a default if a kind is missing.
    subscript(kind: WidgetKind) -> WidgetSettings {
        get { widgets[kind] ?? .default(for: kind, theme: theme) }
        set { widgets[kind] = newValue }
    }

    /// Threshold profile for a widget — a disabled profile when none is set.
    func threshold(for kind: WidgetKind) -> ThresholdProfile {
        thresholds[kind] ?? .disabled
    }

    /// Smoothing settings for a widget — off when none is set.
    func smoothing(for kind: WidgetKind) -> SmoothingSettings {
        smoothing[kind] ?? .off
    }
}

// ── Codable snapshot ─────────────────────────────────────────────────────

extension OverlayConfig {
    /// A plain Codable snapshot — used for presets and per-flight persistence.
    struct Snapshot: Codable {
        var theme: OverlayTheme
        var speedUnits: SpeedUnit
        var altitudeDatum: AltitudeDatum
        var output: OutputSettings
        var messageDisplaySeconds: Double
        var batteryCapacity: Double?
        var gForceScale: Double?
        var distanceUnits: DistanceUnit?
        var showMaxDistance: Bool?
        var mapStyle: FlightMapStyle?
        var mapZoom: Double?
        var mapTrailSeconds: Double?
        var widgets: [WidgetKind: WidgetSettings]
        var thresholds: [WidgetKind: ThresholdProfile]?
        var smoothing: [WidgetKind: SmoothingSettings]?
    }

    var snapshot: Snapshot {
        Snapshot(theme: theme,
                 speedUnits: speedUnits,
                 altitudeDatum: altitudeDatum,
                 output: output,
                 messageDisplaySeconds: messageDisplaySeconds,
                 batteryCapacity: batteryCapacity,
                 gForceScale: gForceScale,
                 distanceUnits: distanceUnits,
                 showMaxDistance: showMaxDistance,
                 mapStyle: mapStyle,
                 mapZoom: mapZoom,
                 mapTrailSeconds: mapTrailSeconds,
                 widgets: widgets,
                 thresholds: thresholds,
                 smoothing: smoothing)
    }

    convenience init(snapshot: Snapshot) {
        self.init(theme: snapshot.theme,
                  speedUnits: snapshot.speedUnits,
                  altitudeDatum: snapshot.altitudeDatum,
                  output: snapshot.output,
                  messageDisplaySeconds: snapshot.messageDisplaySeconds,
                  batteryCapacity: snapshot.batteryCapacity ?? 5000,
                  gForceScale: snapshot.gForceScale ?? 2,
                  distanceUnits: snapshot.distanceUnits ?? .meters,
                  showMaxDistance: snapshot.showMaxDistance ?? true,
                  mapStyle: snapshot.mapStyle ?? .standard,
                  mapZoom: snapshot.mapZoom ?? 1,
                  mapTrailSeconds: snapshot.mapTrailSeconds ?? 0,
                  widgets: snapshot.widgets,
                  thresholds: snapshot.thresholds ?? [:],
                  smoothing: snapshot.smoothing ?? [:])
    }
}
