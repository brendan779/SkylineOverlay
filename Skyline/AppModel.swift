import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

/// Root application state — the loaded flight log and optional video, the
/// overlay configuration, the playback timeline, and the export job.
@MainActor
@Observable
final class AppModel {
    var flightLog: FlightLog?
    var logURL: URL?
    var loadError: String?

    var config = OverlayConfig()

    /// The widget currently selected for editing in the Inspector.
    var selectedWidget: WidgetKind?

    /// When on, dragged widgets snap to a grid for easy alignment.
    var snapToGrid = true
    /// Grid divisions along each axis (the snap granularity).
    var gridDivisions = 24

    // ── Timeline ─────────────────────────────────────────────────────────
    /// Playhead position in seconds, on the video timeline (or the log's
    /// timeline when no video is loaded).
    var scrubTime: Double = 0

    /// Seconds the telemetry is shifted relative to the video, to correct
    /// sync. Telemetry is sampled at `scrubTime + timeOffset`.
    var timeOffset: Double = 0

    var isPlaying = false
    /// True while the user is dragging the scrubber — suppresses playback
    /// time updates so the two don't fight.
    var isScrubbing = false

    var hasLog: Bool { flightLog != nil }
    var hasVideo: Bool { player != nil }
    var logDuration: Double { flightLog?.duration() ?? 0 }

    /// Length of the scrub timeline.
    var timelineDuration: Double {
        (hasVideo && videoDuration > 0) ? videoDuration : logDuration
    }

    /// Telemetry time for the current playhead, clamped to the log.
    var telemetryTime: Double {
        min(max(scrubTime + timeOffset, 0), logDuration)
    }

    /// Telemetry interpolated to the current playhead.
    var currentSample: TelemetrySample {
        guard let log = flightLog else { return .placeholder }
        return TelemetrySample.make(from: log, at: telemetryTime, config: config)
    }

    // ── Video ────────────────────────────────────────────────────────────
    var videoURL: URL?
    private(set) var player: AVPlayer?
    var videoDuration: Double = 0
    private var timeObserver: Any?
    private var playbackTimer: Timer?
    private var lastTick: Date?

    // ── Log loading ──────────────────────────────────────────────────────
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

    // ── Video loading ────────────────────────────────────────────────────
    func loadVideo(url: URL) {
        pause()
        removeTimeObserver()

        let asset = AVURLAsset(url: url)
        let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        player.actionAtItemEnd = .pause
        self.player = player
        self.videoURL = url
        self.videoDuration = 0
        addTimeObserver(to: player)
        scrubTime = 0

        Task {
            let seconds = (try? await asset.load(.duration))?.seconds ?? 0
            self.videoDuration = (seconds.isFinite && seconds > 0) ? seconds : 0
        }
    }

    func presentVideoPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        panel.allowsMultipleSelection = false
        panel.message = "Choose the flight video to composite behind the overlay"
        if panel.runModal() == .OK, let url = panel.url {
            loadVideo(url: url)
        }
    }

    func clearVideo() {
        pause()
        removeTimeObserver()
        player = nil
        videoURL = nil
        videoDuration = 0
        scrubTime = min(scrubTime, timelineDuration)
    }

    // ── Playback ─────────────────────────────────────────────────────────
    func togglePlayback() { isPlaying ? pause() : play() }

    func play() {
        guard hasLog, timelineDuration > 0 else { return }
        if scrubTime >= timelineDuration - 0.05 { seek(to: 0) }
        isPlaying = true
        if let player {
            player.play()
        } else {
            startTimer()
        }
    }

    func pause() {
        isPlaying = false
        player?.pause()
        stopTimer()
    }

    func seek(to time: Double) {
        let clamped = min(max(time, 0), max(timelineDuration, 0))
        scrubTime = clamped
        player?.seek(to: CMTime(seconds: clamped, preferredTimescale: 600),
                     toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func addTimeObserver(to player: AVPlayer) {
        let interval = CMTime(seconds: 1.0 / 30, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.isScrubbing else { return }
                let seconds = time.seconds
                if seconds.isFinite { self.scrubTime = seconds }
                if self.isPlaying, self.timelineDuration > 0,
                   seconds >= self.timelineDuration - 0.03 {
                    self.pause()
                }
            }
        }
    }

    private func removeTimeObserver() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
    }

    private func startTimer() {
        stopTimer()
        lastTick = Date()
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        playbackTimer = timer
    }

    private func stopTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
        lastTick = nil
    }

    private func tick() {
        guard isPlaying, let last = lastTick else { return }
        let now = Date()
        lastTick = now
        let next = scrubTime + now.timeIntervalSince(last)
        if next >= timelineDuration {
            scrubTime = timelineDuration
            pause()
        } else {
            scrubTime = next
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

        // Match the video's length and sync offset so the exported overlay
        // lines up with the footage in an editor.
        let exportDuration: Double? = hasVideo && videoDuration > 0
            ? videoDuration : nil
        let offset = timeOffset

        let exporter = VideoExporter()
        self.exporter = exporter
        renderPhase = .rendering(0)
        Task { @MainActor in
            do {
                try await exporter.export(log: log, config: config, to: url,
                                          duration: exportDuration,
                                          timeOffset: offset) { p in
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
