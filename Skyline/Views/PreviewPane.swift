import SwiftUI
import UniformTypeIdentifiers

/// Centre pane — the 16:9 preview frame (video backdrop + overlay) and the
/// scrub bar, or an empty drop-zone state when no log is loaded.
struct PreviewPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let frame = Self.fit(aspect: 16.0 / 9.0, in: geo.size)
                ZStack {
                    if model.hasLog {
                        loadedFrame(frame)
                    } else {
                        emptyFrame(frame)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .padding(24)

            if model.hasLog {
                ScrubBar()
            }
        }
        .background(Theme.previewBackground)
        .dropDestination(for: URL.self) { urls, _ in
            if let bin = urls.first(where: { $0.pathExtension.lowercased() == "bin" }) {
                model.loadLog(url: bin)
                return true
            }
            if let video = urls.first(where: {
                ["mov", "mp4", "m4v"].contains($0.pathExtension.lowercased())
            }) {
                model.loadVideo(url: video)
                return true
            }
            return false
        }
    }

    private func loadedFrame(_ size: CGSize) -> some View {
        ZStack {
            if let player = model.player {
                PlayerView(player: player)
            } else {
                VideoBackdrop()
            }
            OverlayView(config: model.config, sample: model.currentSample,
                        frameSize: size)
            WidgetInteractionLayer(frameSize: size)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 12)
        .contentShape(Rectangle())
        .onTapGesture { model.selectedWidget = nil }
    }

    private func emptyFrame(_ size: CGSize) -> some View {
        ZStack {
            VideoBackdrop(caption: "")
            VStack(spacing: 16) {
                Image(systemName: "arrow.up.doc")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 84, height: 84)
                    .background(
                        RoundedRectangle(cornerRadius: 22)
                            .strokeBorder(Theme.accent.opacity(0.4),
                                          style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                            .background(Theme.accent.opacity(0.06)))
                VStack(spacing: 6) {
                    Text("Drop a flight log to begin")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("ArduPilot .bin dataflash log")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textTertiary)
                }
                Button("Choose File…") { model.presentOpenPanel() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                if let error = model.loadError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.errorText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// Largest box of the given aspect ratio that fits inside `size`.
    static func fit(aspect: CGFloat, in size: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        if size.width / size.height > aspect {
            return CGSize(width: size.height * aspect, height: size.height)
        }
        return CGSize(width: size.width, height: size.width / aspect)
    }
}
