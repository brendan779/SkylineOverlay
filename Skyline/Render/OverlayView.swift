import SwiftUI

/// Composes every enabled widget over a transparent frame.
///
/// Used for both the live preview and (rasterised) video export, so the two
/// always match. Widgets are authored against a 1080p reference; everything
/// scales with `frameSize.height`.
struct OverlayView: View {
    var config: OverlayConfig
    var sample: TelemetrySample
    var frameSize: CGSize

    private static let referenceHeight: CGFloat = 1080

    private var outputScale: CGFloat { frameSize.height / Self.referenceHeight }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(WidgetKind.allCases) { kind in
                let settings = config[kind]
                if settings.isEnabled {
                    let size = pixelSize(for: kind, settings: settings)
                    widget(kind, settings: settings, size: size)
                        .opacity(settings.opacity)
                        .position(x: settings.position.x * frameSize.width,
                                  y: settings.position.y * frameSize.height)
                }
            }
        }
        .frame(width: frameSize.width, height: frameSize.height)
    }

    private func pixelSize(for kind: WidgetKind,
                           settings: WidgetSettings) -> CGSize {
        CGSize(width: kind.designSize.width * settings.scale * outputScale,
               height: kind.designSize.height * settings.scale * outputScale)
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
        case .wind:
            WindCompassWidget(settings: settings, theme: config.theme,
                              windVN: sample.windVN, windVE: sample.windVE,
                              yaw: sample.yaw, hasWind: sample.hasWind,
                              speedUnit: config.speedUnits, size: size)
        }
    }
}
