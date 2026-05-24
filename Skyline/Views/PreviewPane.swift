import SwiftUI
import UniformTypeIdentifiers

/// Centre pane — the 16:9 preview frame (video backdrop + overlay) and the
/// scrub bar, or an empty drop-zone state when there's no data source.
struct PreviewPane: View {
    @Environment(AppModel.self) private var model
    @State private var showTelemetrySheet = false
    @State private var showVideoSheet = false

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let frame = Self.fit(aspect: 16.0 / 9.0, in: geo.size)
                ZStack {
                    if model.hasSource || model.isLiveVideo {
                        loadedFrame(frame)
                    } else {
                        emptyFrame(frame)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .padding(24)

            // ScrubBar is meaningful only in logged mode — live has no
            // timeline.
            if model.hasSource && !model.isLive {
                ScrubBar()
            } else if model.isLive {
                liveStatusBar
            }
        }
        .sheet(isPresented: $showTelemetrySheet) {
            ConnectTelemetrySheet()
                .environment(model)
        }
        .sheet(isPresented: $showVideoSheet) {
            ConnectVideoSheet()
                .environment(model)
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
            // Backdrop priority: live RTSP → loaded video file → placeholder.
            if model.isLiveVideo {
                VLCVideoNSView(stream: model.liveVideo)
            } else if let player = model.player {
                PlayerView(player: player)
            } else {
                VideoBackdrop()
            }
            // Only draw the HUD when there's a telemetry source — placeholder
            // widgets over a live video would be misleading.
            if model.hasSource {
                OverlayView(config: model.config, sample: model.currentSample,
                            frameSize: size, mapSnapshot: model.mapSnapshot)
                WidgetInteractionLayer(frameSize: size)
            }
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
                HStack(spacing: 10) {
                    Button("Choose File…") { model.presentOpenPanel() }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                    Button("Connect Radio…") { showTelemetrySheet = true }
                        .buttonStyle(.bordered)
                    Button("Connect Video…") { showVideoSheet = true }
                        .buttonStyle(.bordered)
                }
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

    /// Compact "live" indicator that replaces the scrub bar in live mode.
    /// Shows the port + baud + frame count and a disconnect button.
    private var liveStatusBar: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(model.liveTelemetry.isConnected
                      ? Theme.trafficGreen : Theme.error)
                .frame(width: 7, height: 7)
            Text("LIVE")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            if case let .connected(port, baud) = model.liveTelemetry.status {
                Text("\(port.replacingOccurrences(of: "/dev/", with: "")) · \(baud)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                Text("\(model.liveTelemetry.frameCount) frames")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer()
            Button("Disconnect") { model.disconnectTelemetryRadio() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
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
