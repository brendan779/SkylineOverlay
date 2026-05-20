import SwiftUI
import MapKit

/// Maps widget settings to pixel rectangles within a frame. Shared by the
/// renderer and the preview's drag layer so hit areas match what's drawn.
struct OverlayLayout {
    var config: OverlayConfig
    var frameSize: CGSize

    static let referenceHeight: CGFloat = 1080

    private var outputScale: CGFloat { frameSize.height / Self.referenceHeight }

    func size(for kind: WidgetKind) -> CGSize {
        let s = config[kind].scale
        let design = designSize(for: kind)
        return CGSize(width: design.width * s * outputScale,
                      height: design.height * s * outputScale)
    }

    /// Per-kind design size. Most widgets use the static `kind.designSize`,
    /// but the Motors widget grows wider with the number of channels the
    /// user has configured so each bar keeps a consistent visual size.
    private func designSize(for kind: WidgetKind) -> CGSize {
        switch kind {
        case .motors:
            let n = max(1, config.motorWidget.channels.count)
            // Side padding + per-bar lane (≈ bar + gap).
            let width = max(70.0, 22.0 + 26.0 * Double(n))
            return CGSize(width: width, height: kind.designSize.height)
        default:
            return kind.designSize
        }
    }

    func rect(for kind: WidgetKind) -> CGRect {
        let size = size(for: kind)
        let pos = config[kind].position
        return CGRect(x: pos.x * frameSize.width - size.width / 2,
                      y: pos.y * frameSize.height - size.height / 2,
                      width: size.width, height: size.height)
    }
}

/// Composes every enabled widget over a transparent frame.
///
/// Used for both the live preview and (rasterised) video export, so the two
/// always match. Widgets are authored against a 1080p reference; everything
/// scales with `frameSize.height`.
struct OverlayView: View {
    var config: OverlayConfig
    var sample: TelemetrySample
    var frameSize: CGSize
    /// Cached MapKit snapshot for the GPS Map widget; nil until it renders.
    var mapSnapshot: FlightMapImage? = nil

    var body: some View {
        let layout = OverlayLayout(config: config, frameSize: frameSize)
        ZStack(alignment: .topLeading) {
            ForEach(WidgetKind.allCases) { kind in
                let settings = config[kind]
                if settings.isEnabled {
                    let rect = layout.rect(for: kind)
                    widget(kind, settings: settings, size: rect.size)
                        .opacity(settings.opacity * sample.overlayOpacityScale)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
        }
        .frame(width: frameSize.width, height: frameSize.height)
    }

    /// The threshold colour for a widget at the current sample, or nil when
    /// the widget has no profile, it is disabled, or the kind is unsupported.
    private func thresholdColor(_ kind: WidgetKind) -> Color? {
        let profile = config.threshold(for: kind)
        guard profile.isEnabled else { return nil }
        let metric: Double
        switch kind {
        case .groundSpeed: metric = config.speedUnits.convert(sample.groundSpeed)
        case .airSpeed:    metric = config.speedUnits.convert(sample.airSpeed)
        case .altitude:    metric = sample.altitude
        case .battery:     metric = sample.batteryVoltage
        case .gforce:      metric = sample.gForce.lateralMagnitude
        default:           return nil
        }
        return profile.color(for: metric)?.color
    }

    @ViewBuilder
    private func widget(_ kind: WidgetKind, settings: WidgetSettings,
                        size: CGSize) -> some View {
        switch kind {
        case .groundSpeed:
            TapeWidget(settings: settings, theme: config.theme,
                       value: config.speedUnits.convert(sample.groundSpeed),
                       unit: config.speedUnits.label, label: "GND SPD",
                       thresholdColor: thresholdColor(kind), size: size)
        case .airSpeed:
            TapeWidget(settings: settings, theme: config.theme,
                       value: config.speedUnits.convert(sample.airSpeed),
                       unit: config.speedUnits.label, label: "AIR SPD",
                       thresholdColor: thresholdColor(kind), size: size)
        case .altitude:
            TapeWidget(settings: settings, theme: config.theme,
                       value: sample.altitude, unit: "m", label: "ALT",
                       thresholdColor: thresholdColor(kind), size: size)
        case .flightMode:
            ModePillWidget(settings: settings, theme: config.theme,
                           mode: sample.mode, size: size)
        case .messages:
            MessagesWidget(settings: settings, theme: config.theme,
                           messages: sample.messages,
                           window: config.messageDisplaySeconds, size: size)
        case .attitude:
            ArtificialHorizonWidget(settings: settings, theme: config.theme,
                                    pitch: sample.pitch, roll: sample.roll, size: size)
        case .heading:
            HeadingCompassWidget(settings: settings, theme: config.theme,
                                 heading: sample.yaw, size: size)
        case .verticalSpeed:
            VerticalSpeedWidget(settings: settings, theme: config.theme,
                                verticalSpeed: sample.verticalSpeed, size: size)
        case .motors:
            MotorBarWidget(settings: settings, theme: config.theme,
                           motors: sample.motors, size: size)
        case .rangefinder:
            RangefinderWidget(settings: settings, theme: config.theme,
                              distance: sample.rangefinder,
                              dataOpacity: sample.rangefinderOpacity, size: size)
        case .battery:
            BatteryWidget(settings: settings, theme: config.theme,
                          voltage: sample.batteryVoltage,
                          current: sample.batteryCurrent,
                          consumed: sample.batteryConsumed,
                          capacity: config.batteryCapacity,
                          hasData: sample.hasBattery,
                          thresholdColor: thresholdColor(kind), size: size)
        case .gforce:
            GForceWidget(settings: settings, theme: config.theme,
                         gForce: sample.gForce, maxG: config.gForceScale,
                         hasData: sample.hasIMU,
                         thresholdColor: thresholdColor(kind), size: size)
        case .distance:
            DistanceWidget(settings: settings, theme: config.theme,
                           distance: sample.distanceFromHome,
                           maxDistance: sample.maxDistanceFromHome,
                           unit: config.distanceUnits,
                           showMax: config.showMaxDistance,
                           hasHome: sample.hasHome, size: size)
        case .map:
            GPSMapWidget(settings: settings, theme: config.theme,
                         snapshot: mapSnapshot,
                         track: sample.track,
                         currentTime: sample.time,
                         currentCoord: sample.coordinate,
                         home: sample.home,
                         trailSeconds: config.mapTrailSeconds,
                         zoom: config.mapZoom, size: size)
        case .wind:
            WindCompassWidget(settings: settings, theme: config.theme,
                              windVN: sample.windVN, windVE: sample.windVE,
                              yaw: sample.yaw, hasWind: sample.hasWind,
                              speedUnit: config.speedUnits, size: size)
        }
    }
}
