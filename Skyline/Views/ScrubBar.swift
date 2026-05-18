import SwiftUI

/// Timeline scrubber under the preview frame.
struct ScrubBar: View {
    @Binding var time: Double
    var duration: Double

    var body: some View {
        HStack(spacing: 12) {
            Text(Self.timecode(time))
                .frame(width: 70, alignment: .leading)
            Slider(value: $time, in: 0...max(duration, 0.001))
                .controlSize(.small)
                .disabled(duration <= 0)
            Text(Self.timecode(duration))
                .frame(width: 70, alignment: .trailing)
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
