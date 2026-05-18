import SwiftUI

/// Status-message widget — shows the two most recent log messages,
/// right-aligned, fading out as they age past the display window.
struct MessagesWidget: View {
    var settings: WidgetSettings
    var theme: OverlayTheme
    var messages: [TelemetrySample.Message]
    var window: Double
    var size: CGSize

    var body: some View {
        let h = size.height
        ZStack {
            RoundedRectangle(cornerRadius: h * 0.14)
                .fill(settings.background.color)
            RoundedRectangle(cornerRadius: h * 0.14)
                .stroke(.white.opacity(0.22), lineWidth: 1)

            VStack(alignment: .trailing, spacing: h * 0.05) {
                Text("MESSAGES")
                    .font(condensed(h * 0.15))
                    .foregroundStyle(theme.label.color)
                Spacer(minLength: 0)
                ForEach(Array(messages.suffix(2).enumerated()), id: \.offset) { _, msg in
                    Text(msg.text)
                        .font(condensed(h * 0.22, weight: .regular))
                        .foregroundStyle(color(for: msg))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .padding(.horizontal, h * 0.14)
            .padding(.vertical, h * 0.11)
        }
        .frame(width: size.width, height: size.height)
    }

    private func color(for msg: TelemetrySample.Message) -> Color {
        let base = msg.severity <= 3 ? theme.warning : theme.message
        let fade = max(0.25, 1 - msg.age / window)
        return base.opacity(fade).color
    }

    private func condensed(_ size: CGFloat,
                           weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }
}
