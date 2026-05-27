import SwiftUI
import AVFoundation

/// Modal sheet for picking a USB UVC capture device and starting live
/// video from it.
struct ConnectCaptureCardSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var devices: [AVCaptureDevice] = LiveCaptureCard.availableDevices()
    @State private var selectedID: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Connect capture card")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button { devices = LiveCaptureCard.availableDevices() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)
                .help("Refresh device list")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Capture device")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                if devices.isEmpty {
                    Text("No capture devices found. Plug in a USB-C capture "
                         + "card and tap refresh.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textMuted)
                        .padding(.vertical, 4)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Picker("", selection: $selectedID) {
                        ForEach(devices, id: \.uniqueID) { d in
                            Text(d.localizedName).tag(d.uniqueID)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .pickerStyle(.menu)
                }
            }

            statusLine

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Connect") {
                    if let device = devices.first(where: { $0.uniqueID == selectedID }) {
                        model.connectCaptureCard(device: device)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: 0x3FA9FF))
                .disabled(selectedID.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 380)
        .background(Theme.surface)
        .onAppear { restoreLastUsed() }
    }

    @ViewBuilder
    private var statusLine: some View {
        if case .failed(let msg) = model.liveCaptureCard.status {
            Text(msg)
                .font(.system(size: 10))
                .foregroundStyle(Theme.errorText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Restore the previously-used device if it's still attached; otherwise
    /// pick the first available.
    private func restoreLastUsed() {
        let last = UserDefaults.standard
            .string(forKey: "Skyline.captureCard.deviceID") ?? ""
        if !last.isEmpty, devices.contains(where: { $0.uniqueID == last }) {
            selectedID = last
        } else {
            selectedID = devices.first?.uniqueID ?? ""
        }
    }
}
