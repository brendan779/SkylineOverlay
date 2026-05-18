import SwiftUI

/// Timeline scrubber and transport under the preview frame.
struct ScrubBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            Button {
                model.togglePlayback()
            } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 12))
                    .frame(width: 18)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textPrimary)
            .disabled(model.timelineDuration <= 0)

            Text(Self.timecode(model.scrubTime))
                .frame(width: 64, alignment: .leading)

            Slider(
                value: Binding { model.scrubTime } set: { model.seek(to: $0) },
                in: 0...max(model.timelineDuration, 0.001),
                onEditingChanged: { model.isScrubbing = $0 })
                .controlSize(.small)
                .disabled(model.timelineDuration <= 0)

            Text(Self.timecode(model.timelineDuration))
                .frame(width: 64, alignment: .trailing)
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(Theme.textTertiary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    static func timecode(_ seconds: Double) -> String {
        let t = Int(seconds.rounded())
        return String(format: "%02d:%02d:%02d", t / 3600, (t / 60) % 60, t % 60)
    }
}
