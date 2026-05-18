import SwiftUI

/// Flight-mode widget — a "MODE" label beside an accent pill naming the
/// current ArduPilot flight mode.
struct ModePillWidget: View {
    var settings: WidgetSettings
    var theme: OverlayTheme
    var mode: String
    var size: CGSize

    var body: some View {
        let h = size.height
        ZStack {
            RoundedRectangle(cornerRadius: h * 0.22)
                .fill(settings.background.color)
            RoundedRectangle(cornerRadius: h * 0.22)
                .stroke(.white.opacity(0.22), lineWidth: 1)

            HStack(spacing: 0) {
                Text("MODE")
                    .font(condensed(h * 0.30))
                    .foregroundStyle(theme.label.color)
                Spacer(minLength: h * 0.18)
                HStack(spacing: h * 0.16) {
                    Circle()
                        .fill(settings.accent.color)
                        .frame(width: h * 0.16, height: h * 0.16)
                    Text(mode)
                        .font(condensed(h * 0.40, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, h * 0.22)
                .padding(.vertical, h * 0.13)
                .background(
                    RoundedRectangle(cornerRadius: h * 0.16)
                        .fill(settings.accent.color.opacity(0.85)))
            }
            .padding(.horizontal, h * 0.24)
        }
        .frame(width: size.width, height: size.height)
    }

    private func condensed(_ size: CGFloat,
                           weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }
}
