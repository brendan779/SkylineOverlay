import SwiftUI

#if canImport(VLCKit)
import VLCKit
#endif

/// Left pane — brand, the flight-log and video import actions, and the
/// loaded files.
struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @State private var showTelemetrySheet = false
    @State private var showVideoSheet = false

    private let videoAccent = Color(hex: 0x3FA9FF)
    private let liveAccent = Color(hex: 0xFFB347)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: Theme.titleBarHeight)   // traffic-light row

            brand
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            importButton("Open Flight Log") { model.presentOpenPanel() }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            importButton("Connect Telemetry Radio") {
                showTelemetrySheet = true
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 14)

            sectionHeader("Flights")
            if model.isLive {
                liveRadioRow
            } else if let url = model.logURL {
                fileRow(badge: "BIN", name: url.lastPathComponent,
                        accent: Theme.accent)
            } else {
                emptyHint("No log loaded")
            }

            Spacer()

            sectionHeader("Video")
            VStack(spacing: 6) {
                importButton("Import Video") { model.presentVideoPanel() }
#if canImport(VLCKit)
                importButton("Connect Video Stream") { showVideoSheet = true }
#endif
            }
            .padding(.horizontal, 12)
            .padding(.top, 2)
            .padding(.bottom, 8)
            if model.isLiveVideo {
                liveVideoRow
            } else if let url = model.videoURL {
                fileRow(badge: url.pathExtension.uppercased(),
                        name: url.lastPathComponent,
                        accent: videoAccent,
                        onRemove: { model.clearVideo() })
            } else {
                emptyHint("Optional — composites behind the overlay")
            }

            Spacer()
        }
        .frame(width: Theme.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(Theme.surface)
        .sheet(isPresented: $showTelemetrySheet) {
            ConnectTelemetrySheet().environment(model)
        }
        .sheet(isPresented: $showVideoSheet) {
            ConnectVideoSheet().environment(model)
        }
    }

    /// Sidebar row shown when a live RTSP stream is connected.
    private var liveVideoRow: some View {
        let urlLabel: String = {
            if case let .playing(url) = model.liveVideo.status { return url }
            if case let .connecting(url) = model.liveVideo.status { return url }
            return model.liveVideo.lastConnectedURL
        }()
        return fileRow(badge: "RTSP",
                       name: urlLabel.replacingOccurrences(of: "rtsp://", with: ""),
                       accent: videoAccent,
                       onRemove: { model.disconnectVideoStream() })
    }

    /// Sidebar row shown when a live MAVLink radio is connected — mirrors
    /// the file row layout but with a live-orange accent and a disconnect
    /// affordance.
    private var liveRadioRow: some View {
        let status = model.liveTelemetry.status
        let label: String = {
            if case let .connected(port, baud) = status {
                let short = port.replacingOccurrences(of: "/dev/cu.", with: "")
                return "\(short)  ·  \(baud)"
            }
            return "Connecting…"
        }()
        return fileRow(badge: "LIVE", name: label, accent: liveAccent,
                       onRemove: { model.disconnectTelemetryRadio() })
    }

    private var brand: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: [Theme.accent, Theme.accent.opacity(0.5)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 22, height: 22)
                .overlay(Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.black))
            Text("Skyline")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text("BETA")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textMuted)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .overlay(RoundedRectangle(cornerRadius: 3)
                    .stroke(Theme.borderStrong, lineWidth: 0.5))
        }
    }

    private func importButton(_ title: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                Text(title).font(.system(size: 12))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(Theme.borderStrong, lineWidth: 0.5))
        .foregroundStyle(Theme.textPrimary)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Theme.textMuted)
            .padding(.horizontal, 18)
            .padding(.bottom, 6)
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Theme.textMuted)
            .padding(.horizontal, 18)
            .padding(.top, 2)
    }

    private func fileRow(badge: String, name: String, accent: Color,
                         onRemove: (() -> Void)? = nil) -> some View {
        HStack(spacing: 9) {
            Text(badge)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 5)
                    .fill(accent.opacity(0.13)))
            Text(name)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1).truncationMode(.middle)
            Spacer()
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textMuted)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.07)))
        .padding(.horizontal, 8)
    }
}
