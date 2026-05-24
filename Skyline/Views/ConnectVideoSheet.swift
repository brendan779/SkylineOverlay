import SwiftUI

/// Modal sheet for entering an RTSP / RTP / UDP URL and starting the live
/// video stream. Default pre-fills the user's Cosmostreamer Pi.
struct ConnectVideoSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var url: String = ""

    /// User-configurable default — Cosmostreamer Pi at home.
    private static let defaultURL = "rtsp://192.168.50.1:554/video"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect video stream")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Stream URL")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                TextField("rtsp://…", text: $url)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .controlSize(.small)
                Text("RTSP, RTP, MPEG‑TS or UDP. Cosmostreamer over Ethernet works well.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textMuted)
            }

#if !canImport(VLCKit)
            Text("VLCKit isn't linked — see Skyline/Video/VIDEOKIT_SETUP.md "
                 + "to enable RTSP playback.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.errorText)
                .fixedSize(horizontal: false, vertical: true)
#endif

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Connect") {
                    model.connectVideoStream(url: url)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: 0x3FA9FF))
                .disabled(url.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 380)
        .background(Theme.surface)
        .onAppear { restoreLastUsed() }
    }

    private func restoreLastUsed() {
        let last = UserDefaults.standard.string(forKey: "Skyline.video.url") ?? ""
        url = last.isEmpty ? Self.defaultURL : last
    }
}
