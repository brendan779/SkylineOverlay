import SwiftUI

/// Maps widget settings to pixel rectangles within a frame. Shared by the
/// renderer and the preview's drag layer so hit areas match what's drawn.
struct OverlayLayout {
    var config: OverlayConfig
    var frameSize: CGSize

    static let referenceHeight: CGFloat = 1080

    private var outputScale: CGFloat { frameSize.height / Self.referenceHeight }

    func size(for kind: WidgetKind) -> CGSize {
        let s = config[kind].scale
        return CGSize(width: kind.designSize.width * s * outputScale,
                      height: kind.designSize.height * s * outputScale)
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

    var body: some View {
        let layout = OverlayLayout(config: config, frameSize: frameSize)
        ZStack(alignment: .topLeading) {
            ForEach(WidgetKind.allCases) { kind in
                let settings = config[kind]
                if settings.isEnabled {
                    let rect = layout.rect(for: kind)
                    widget(kind, settings: settings, size: rect.size)
                        .opacity(settings.opacity)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
        }
        .frame(width: frameSize.width, height: frameSize.height)
    }

    @ViewBuilder
    private func widget(_ kind: WidgetKind, settings: WidgetSettings,
                        size: CGSize) -> some View {
        switch kind {
        case .groundSpeed:
            TapeWidget(settings: settings, theme: config.theme,
                       value: config.speedUnits.convert(sample.groundSpeed),
                       unit: config.speedUnits.label, label: "GND SPD", size: size)
        case .airSpeed:
            TapeWidget(settings: settings, theme: config.theme,
                       value: config.speedUnits.convert(sample.airSpeed),
                       unit: config.speedUnits.label, label: "AIR SPD", size: size)
        case .altitude:
            TapeWidget(settings: settings, theme: config.theme,
                       value: sample.altitude, unit: "m", label: "ALT", size: size)
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
                           throttle: sample.throttle,
                           liftMotors: sample.liftMotors, size: size)
        case .rangefinder:
            RangefinderWidget(settings: settings, theme: config.theme,
                              distance: sample.rangefinder,
                              dataOpacity: sample.rangefinderOpacity, size: size)
        case .wind:
            WindCompassWidget(settings: settings, theme: config.theme,
                              windVN: sample.windVN, windVE: sample.windVE,
                              yaw: sample.yaw, hasWind: sample.hasWind,
                              speedUnit: config.speedUnits, size: size)
        }
    }
}
