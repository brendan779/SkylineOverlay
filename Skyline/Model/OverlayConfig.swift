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

    /// Default placements reproduce the renderer's lower-third layout.
    private static func defaultPosition(for kind: WidgetKind) -> CGPoint {
        switch kind {
        case .groundSpeed:   return CGPoint(x: 0.08, y: 0.86)
        case .airSpeed:      return CGPoint(x: 0.20, y: 0.86)
        case .wind:          return CGPoint(x: 0.31, y: 0.86)
        case .altitude:      return CGPoint(x: 0.40, y: 0.86)
        case .attitude:      return CGPoint(x: 0.50, y: 0.84)
        case .heading:       return CGPoint(x: 0.50, y: 0.94)
        case .verticalSpeed: return CGPoint(x: 0.60, y: 0.86)
        case .flightMode:    return CGPoint(x: 0.86, y: 0.82)
        case .messages:      return CGPoint(x: 0.83, y: 0.91)
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
    var widgets: [WidgetKind: WidgetSettings]

    init(theme: OverlayTheme = .default,
         speedUnits: SpeedUnit = .kmh,
         altitudeDatum: AltitudeDatum = .relative,
         output: OutputSettings = .default,
         messageDisplaySeconds: Double = 4.0,
         widgets: [WidgetKind: WidgetSettings]? = nil) {
        self.theme = theme
        self.speedUnits = speedUnits
        self.altitudeDatum = altitudeDatum
        self.output = output
        self.messageDisplaySeconds = messageDisplaySeconds
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
        var widgets: [WidgetKind: WidgetSettings]
    }

    var snapshot: Snapshot {
        Snapshot(theme: theme,
                 speedUnits: speedUnits,
                 altitudeDatum: altitudeDatum,
                 output: output,
                 messageDisplaySeconds: messageDisplaySeconds,
                 widgets: widgets)
    }

    convenience init(snapshot: Snapshot) {
        self.init(theme: snapshot.theme,
                  speedUnits: snapshot.speedUnits,
                  altitudeDatum: snapshot.altitudeDatum,
                  output: snapshot.output,
                  messageDisplaySeconds: snapshot.messageDisplaySeconds,
                  widgets: snapshot.widgets)
    }
}
