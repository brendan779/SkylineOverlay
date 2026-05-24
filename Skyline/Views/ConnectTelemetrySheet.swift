import SwiftUI

/// Modal sheet for picking a serial port + baud rate and connecting the
/// live MAVLink telemetry radio.
struct ConnectTelemetrySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var ports: [String] = Serial.availablePorts()
    @State private var selectedPort: String = ""
    @State private var selectedBaud: Int = 57600

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Connect telemetry radio")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button { ports = Serial.availablePorts() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)
                .help("Refresh port list")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Serial port")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                if ports.isEmpty {
                    Text("No USB-serial devices found. Plug in the radio and tap refresh.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textMuted)
                        .padding(.vertical, 4)
                } else {
                    Picker("", selection: $selectedPort) {
                        ForEach(ports, id: \.self) { p in
                            Text(p).font(.system(size: 11, design: .monospaced))
                                .tag(p)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Baud rate")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                Picker("", selection: $selectedBaud) {
                    ForEach(Serial.commonBaudRates, id: \.self) { b in
                        Text("\(b)").tag(b)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .pickerStyle(.menu)
            }

            // Status line — pulls live state from the model.
            statusLine

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Connect") {
                    model.connectTelemetryRadio(port: selectedPort,
                                                baud: selectedBaud)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(selectedPort.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 360)
        .background(Theme.surface)
        .onAppear { restoreLastUsed() }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch model.liveTelemetry.status {
        case .failed(let msg):
            Text(msg)
                .font(.system(size: 10))
                .foregroundStyle(Theme.errorText)
        default:
            EmptyView()
        }
    }

    /// Pre-fill from the last successful connection so reconnecting is
    /// one click.
    private func restoreLastUsed() {
        let defaults = UserDefaults.standard
        let lastPort = defaults.string(forKey: "Skyline.live.port") ?? ""
        let lastBaud = defaults.integer(forKey: "Skyline.live.baud")
        if !lastPort.isEmpty, ports.contains(lastPort) {
            selectedPort = lastPort
        } else {
            selectedPort = ports.first ?? ""
        }
        if Serial.commonBaudRates.contains(lastBaud) {
            selectedBaud = lastBaud
        }
    }
}
