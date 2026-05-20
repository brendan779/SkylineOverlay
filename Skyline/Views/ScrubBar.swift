import SwiftUI

/// Timeline scrubber and transport under the preview frame.
///
/// Above the basic play/pause + slider, the bar also marks an optional
/// in/out range — like a video-editor trim — so the user can render just
/// that slice from the Inspector's Render button.
struct ScrubBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
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

            rangeButton("[", help: "Set range in-point at playhead (I)",
                        shortcut: "i") { model.setRangeStart() }

            timelineTrack

            rangeButton("]", help: "Set range out-point at playhead (O)",
                        shortcut: "o") { model.setRangeEnd() }

            if model.hasRange {
                Button { model.clearRange() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textMuted)
                .help("Clear render range")
            }

            Text(Self.timecode(model.timelineDuration))
                .frame(width: 64, alignment: .trailing)
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(Theme.textTertiary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    /// The scrub slider with an accent band drawn behind it showing the
    /// marked in/out range.
    private var timelineTrack: some View {
        ZStack {
            GeometryReader { geo in
                if model.hasRange, let band = rangeBand(in: geo.size.width) {
                    Rectangle()
                        .fill(Theme.accent.opacity(0.28))
                        .frame(width: band.width, height: 6)
                        .offset(x: band.x,
                                y: (geo.size.height - 6) / 2)
                }
            }
            .allowsHitTesting(false)

            Slider(
                value: Binding { model.scrubTime } set: { model.seek(to: $0) },
                in: 0...max(model.timelineDuration, 0.001),
                onEditingChanged: { model.isScrubbing = $0 })
                .controlSize(.small)
                .disabled(model.timelineDuration <= 0)
        }
    }

    /// Position and width of the selection band, in the slider's local
    /// coordinate space. The slider's thumb inset is opaque, so this is an
    /// approximation — close enough to read at a glance.
    private func rangeBand(in width: CGFloat) -> (x: CGFloat, width: CGFloat)? {
        guard let s = model.rangeStart, let e = model.rangeEnd,
              model.timelineDuration > 0 else { return nil }
        let inset: CGFloat = 8
        let usable = max(0, width - inset * 2)
        let lo = CGFloat(s / model.timelineDuration)
        let hi = CGFloat(e / model.timelineDuration)
        return (x: inset + lo * usable,
                width: max(2, (hi - lo) * usable))
    }

    /// A compact bracket button — sets an in or out point and registers a
    /// keyboard shortcut so the user can hit `I` / `O` like a video editor.
    private func rangeButton(_ label: String, help: String,
                             shortcut: KeyEquivalent,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold,
                              design: .monospaced))
                .frame(width: 14)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textSecondary)
        .help(help)
        .keyboardShortcut(shortcut, modifiers: [])
        .disabled(model.timelineDuration <= 0)
    }

    static func timecode(_ seconds: Double) -> String {
        let t = Int(seconds.rounded())
        return String(format: "%02d:%02d:%02d", t / 3600, (t / 60) % 60, t % 60)
    }
}
