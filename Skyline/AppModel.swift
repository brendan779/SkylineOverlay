import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Root application state — the loaded flight log, the overlay configuration,
/// and the current scrub position. Injected into the view tree.
@Observable
final class AppModel {
    var flightLog: FlightLog?
    var logURL: URL?
    var loadError: String?

    var config = OverlayConfig()

    /// Scrub position in seconds (telemetry time, for now offset-free).
    var scrubTime: Double = 0

    /// The widget currently selected for editing in the Inspector.
    var selectedWidget: WidgetKind?

    var hasLog: Bool { flightLog != nil }
    var duration: Double { flightLog?.duration() ?? 0 }

    /// Telemetry interpolated to the current scrub position.
    var currentSample: TelemetrySample {
        guard let log = flightLog else { return .placeholder }
        return TelemetrySample.make(from: log, at: scrubTime, config: config)
    }

    // ── Loading ──────────────────────────────────────────────────────────
    func loadLog(url: URL) {
        do {
            flightLog = try FlightLog(url: url)
            logURL = url
            loadError = nil
            scrubTime = 0
        } catch {
            flightLog = nil
            logURL = nil
            loadError = "Couldn't read \(url.lastPathComponent) — "
                + "the log may be truncated or from an unsupported firmware."
        }
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "bin") ?? .data]
        panel.allowsMultipleSelection = false
        panel.message = "Choose an ArduPilot .bin dataflash log"
        if panel.runModal() == .OK, let url = panel.url {
            loadLog(url: url)
        }
    }
}
