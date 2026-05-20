import SwiftUI

/// Timeline scrubber and transport under the preview frame.
///
/// A scissors button above play toggles trim mode; in trim mode a yellow
/// frame wraps the slider with draggable chevron handles at each end, like
/// the iOS Photos video trimmer. The marked range feeds the "Render
/// Selected Range" button in the Inspector.
struct ScrubBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            transportButtons

            Text(Self.timecode(model.scrubTime))
                .frame(width: 64, alignment: .leading)

            Slider(
                value: Binding { model.scrubTime } set: { model.seek(to: $0) },
                in: 0...max(model.timelineDuration, 0.001),
                onEditingChanged: { model.isScrubbing = $0 })
                .controlSize(.small)
                .disabled(model.timelineDuration <= 0)
                .overlay(trimOverlay)

            Text(Self.timecode(model.timelineDuration))
                .frame(width: 64, alignment: .trailing)
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(Theme.textTertiary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    /// Stack of the scissors / play buttons on the leading edge.
    private var transportButtons: some View {
        VStack(spacing: 3) {
            Button { model.toggleTrimMode() } label: {
                Image(systemName: "scissors")
                    .font(.system(size: 11))
                    .frame(width: 18, height: 14)
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.trimMode
                             ? Theme.trafficYellow : Theme.textSecondary)
            .help(model.trimMode ? "Exit trim mode"
                                 : "Trim — mark a range to render a slice")
            .disabled(model.timelineDuration <= 0)

            Button { model.togglePlayback() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 12))
                    .frame(width: 18, height: 14)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textPrimary)
            .disabled(model.timelineDuration <= 0)
        }
    }

    /// Yellow trim frame with draggable chevron handles. Lives in the
    /// slider's `.overlay` so the geometry is bounded to the slider and the
    /// scrub-bar height never grows.
    @ViewBuilder
    private var trimOverlay: some View {
        if model.trimMode {
            GeometryReader { geo in
                trimChrome(in: geo.size)
            }
            .coordinateSpace(name: "scrub")
            .allowsHitTesting(true)
        }
    }

    /// Draw the yellow trim box and the two handles, given the slider's
    /// total size.
    private func trimChrome(in size: CGSize) -> some View {
        let inset: CGFloat = 8                       // slider thumb padding
        let usable = max(0, size.width - inset * 2)
        let duration = max(0.001, model.timelineDuration)
        let s = model.rangeStart ?? 0
        let e = model.rangeEnd ?? duration
        let xL = inset + CGFloat(s / duration) * usable
        let xR = inset + CGFloat(e / duration) * usable
        let boxH: CGFloat = max(14, size.height - 2)
        let boxY = (size.height - boxH) / 2
        let yellow = Theme.trafficYellow

        return ZStack {
            // Yellow outline around the trim region.
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(yellow, lineWidth: 2)
                .frame(width: max(8, xR - xL), height: boxH)
                .position(x: (xL + xR) / 2, y: boxY + boxH / 2)
                .allowsHitTesting(false)

            // Chevron handles — the grabbable bits at each end of the box.
            handle(isLeft: true,  x: xL, height: boxH,
                   trackWidth: size.width, trackHeight: size.height)
            handle(isLeft: false, x: xR, height: boxH,
                   trackWidth: size.width, trackHeight: size.height)
        }
    }

    /// One trim handle. A small yellow tab with a chevron, anchored just
    /// outside the trim box edge so dragging it feels like dragging the
    /// wall itself.
    private func handle(isLeft: Bool, x: CGFloat, height: CGFloat,
                        trackWidth: CGFloat, trackHeight: CGFloat) -> some View {
        let tabW: CGFloat = 12
        let inset: CGFloat = 8
        let usable = max(0, trackWidth - inset * 2)
        let duration = max(0.001, model.timelineDuration)
        // Anchor the tab so the chevron sits outside the yellow box edge.
        let anchorX = isLeft ? x - tabW / 2 + 1 : x + tabW / 2 - 1

        // IMPORTANT: contentShape + gesture must come *before* `.position`.
        // `.position` wraps the view in a parent-sized container, so
        // modifiers applied after it bind to the whole parent — which
        // would make one handle hijack every click in the trim area.
        return ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(Theme.trafficYellow)
            Image(systemName: isLeft ? "chevron.compact.left"
                                     : "chevron.compact.right")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.black)
        }
        .frame(width: tabW, height: height + 2)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0,
                        coordinateSpace: .named("scrub"))
                .onChanged { value in
                    let clamped = max(inset,
                                      min(trackWidth - inset, value.location.x))
                    let t = Double((clamped - inset) / max(1, usable)) * duration
                    if isLeft {
                        let upper = (model.rangeEnd ?? duration) - 0.05
                        model.rangeStart = max(0, min(t, upper))
                    } else {
                        let lower = (model.rangeStart ?? 0) + 0.05
                        model.rangeEnd = min(duration, max(t, lower))
                    }
                })
        .position(x: anchorX, y: trackHeight / 2)
    }

    static func timecode(_ seconds: Double) -> String {
        let t = Int(seconds.rounded())
        return String(format: "%02d:%02d:%02d", t / 3600, (t / 60) % 60, t % 60)
    }
}
