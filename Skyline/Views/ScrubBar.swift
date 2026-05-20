import SwiftUI

/// Timeline scrubber and transport under the preview frame.
///
/// Two bracket buttons (`[` / `]`, plus `I` / `O` keyboard shortcuts) mark
/// an optional in/out range — like a video-editor trim — so the user can
/// render just that slice from the Inspector's Render bar.
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

            bracketButton("[", help: "Set in-point at playhead (I)",
                          shortcut: "i") { model.setRangeStart() }

            Slider(
                value: Binding { model.scrubTime } set: { model.seek(to: $0) },
                in: 0...max(model.timelineDuration, 0.001),
                onEditingChanged: { model.isScrubbing = $0 })
                .controlSize(.small)
                .disabled(model.timelineDuration <= 0)
                .background(rangeOverlay)

            bracketButton("]", help: "Set out-point at playhead (O)",
                          shortcut: "o") { model.setRangeEnd() }

            if model.hasRange || model.rangeStart != nil || model.rangeEnd != nil {
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

    /// Tinted band + tick marks drawn on the slider's track.
    ///
    /// Sits in the slider's `.background`, so the `GeometryReader` is sized
    /// to the slider — it never inflates the row. The slider's thumb inset
    /// is opaque, so the alignment is approximate (close enough to read).
    private var rangeOverlay: some View {
        GeometryReader { geo in
            let inset: CGFloat = 8
            let usable = max(0, geo.size.width - inset * 2)
            let yMid = geo.size.height / 2

            // Band between in and out, when both are set.
            if model.hasRange,
               let s = model.rangeStart, let e = model.rangeEnd,
               model.timelineDuration > 0 {
                let x0 = inset + CGFloat(s / model.timelineDuration) * usable
                let x1 = inset + CGFloat(e / model.timelineDuration) * usable
                Rectangle()
                    .fill(Theme.accent.opacity(0.28))
                    .frame(width: max(2, x1 - x0), height: 4)
                    .position(x: (x0 + x1) / 2, y: yMid)
            }
            // Tick at the in-point — visible even before an out-point is set.
            if let s = model.rangeStart, model.timelineDuration > 0 {
                let x = inset + CGFloat(s / model.timelineDuration) * usable
                Rectangle()
                    .fill(Theme.accent)
                    .frame(width: 2, height: 12)
                    .position(x: x, y: yMid)
            }
            // Tick at the out-point.
            if let e = model.rangeEnd, model.timelineDuration > 0 {
                let x = inset + CGFloat(e / model.timelineDuration) * usable
                Rectangle()
                    .fill(Theme.accent)
                    .frame(width: 2, height: 12)
                    .position(x: x, y: yMid)
            }
        }
        .allowsHitTesting(false)
    }

    /// Small bordered bracket button — sets an in or out point and binds the
    /// matching single-key shortcut (`I` / `O`, like a video editor).
    private func bracketButton(_ label: String, help: String,
                               shortcut: KeyEquivalent,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold,
                              design: .monospaced))
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .help(help)
        .keyboardShortcut(shortcut, modifiers: [])
        .disabled(model.timelineDuration <= 0)
    }

    static func timecode(_ seconds: Double) -> String {
        let t = Int(seconds.rounded())
        return String(format: "%02d:%02d:%02d", t / 3600, (t / 60) % 60, t % 60)
    }
}
