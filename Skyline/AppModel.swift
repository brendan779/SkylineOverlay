import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Root application state — the loaded flight log, the overlay configuration,
/// and the current scrub position. Injected into the view tree.
@MainActor
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

    // ── Export ───────────────────────────────────────────────────────────
    enum RenderPhase: Equatable {
        case idle
        case rendering(Double)   // 0...1 progress
        case done(URL)
        case failed(String)
    }

    var renderPhase: RenderPhase = .idle
    private var exporter: VideoExporter?

    var isRendering: Bool {
        if case .rendering = renderPhase { return true }
        return false
    }

    /// Ask for an output location, then render the overlay to a video file.
    func startExport() {
        guard let log = flightLog else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.quickTimeMovie]
        let base = logURL?.deletingPathExtension().lastPathComponent ?? "overlay"
        panel.nameFieldStringValue = "\(base)_overlay.mov"
        panel.message = "Choose where to save the overlay video"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let exporter = VideoExporter()
        self.exporter = exporter
        renderPhase = .rendering(0)
        Task { @MainActor in
            do {
                try await exporter.export(log: log, config: config, to: url) { p in
                    self.renderPhase = .rendering(p.fraction)
                }
                renderPhase = .done(url)
            } catch is CancellationError {
                renderPhase = .idle
            } catch {
                renderPhase = .failed(error.localizedDescription)
            }
            self.exporter = nil
        }
    }

    func cancelExport() {
        exporter?.cancel()
    }

    func resetRender() {
        renderPhase = .idle
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
