import SwiftUI
import AppKit
import AVFoundation
import MapKit
import UniformTypeIdentifiers

/// Root application state — the loaded flight log and optional video, the
/// overlay configuration, the playback timeline, and the export job.
@MainActor
@Observable
final class AppModel {
    /// Where telemetry comes from — a loaded `.bin` log, or a live MAVLink
    /// radio. Mutually exclusive; switching one tears down the other.
    enum Mode { case logged, live }
    var mode: Mode = .logged

    var flightLog: FlightLog?
    var logURL: URL?
    var loadError: String?

    /// Live MAVLink source — owned even when in logged mode, so its
    /// settings (port / baud) survive an unrelated load.
    var liveTelemetry = LiveTelemetry()

    var config = OverlayConfig()

    /// The widget currently selected for editing in the Inspector.
    var selectedWidget: WidgetKind?

    /// When on, dragged widgets snap to a grid for easy alignment.
    var snapToGrid = true
    /// Grid divisions along each axis (the snap granularity).
    var gridDivisions = 48

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

    /// True when there's *any* telemetry source — a loaded log or a live
    /// radio. PreviewPane uses this to decide between empty-state and
    /// loaded-state.
    var hasSource: Bool {
        switch mode {
        case .logged: return hasLog
        case .live:   return liveTelemetry.isConnected
        }
    }

    /// Scrub / trim / export only apply to logged mode.
    var isLive: Bool { mode == .live }

    /// Length of the scrub timeline. In live mode the timeline is "now"
    /// — controls that depend on this hide themselves.
    var timelineDuration: Double {
        if isLive { return 0 }
        return (hasVideo && videoDuration > 0) ? videoDuration : logDuration
    }

    /// Telemetry time for the current playhead, clamped to the log.
    var telemetryTime: Double {
        min(max(scrubTime + timeOffset, 0), logDuration)
    }

    /// Telemetry interpolated to the current playhead — or, in live mode,
    /// a snapshot of the most recent MAVLink frames.
    var currentSample: TelemetrySample {
        switch mode {
        case .logged:
            guard let log = flightLog else { return .placeholder }
            return TelemetrySample.make(from: log, at: telemetryTime, config: config)
        case .live:
            return liveTelemetry.currentSample(config: config)
        }
    }

    // ── Live telemetry connect / disconnect ──────────────────────────────
    func connectTelemetryRadio(port: String, baud: Int,
                               profile: TelemetryLinkProfile) {
        // Drop any loaded log; mutually exclusive sources.
        flightLog = nil
        logURL = nil
        mapSnapshot = nil
        scrubTime = 0
        mode = .live
        liveTelemetry.linkProfile = profile     // applied on first heartbeat
        liveTelemetry.connect(port: port, baud: baud)
        let d = UserDefaults.standard
        d.set(port, forKey: "Skyline.live.port")
        d.set(baud, forKey: "Skyline.live.baud")
        d.set(profile.rawValue, forKey: "Skyline.live.linkProfile")
    }

    func disconnectTelemetryRadio() {
        liveTelemetry.disconnect()
        mode = .logged
    }

    // ── Video ────────────────────────────────────────────────────────────
    var videoURL: URL?
    private(set) var player: AVPlayer?
    var videoDuration: Double = 0
    private var timeObserver: Any?
    private var playbackTimer: Timer?
    private var lastTick: Date?

    /// Live RTSP / network video stream (Cosmostreamer over Ethernet etc.).
    /// Distinct from the loaded-file `player` — either can be active, with
    /// live taking precedence in the preview.
    var liveVideo = LiveVideoStream()
    var isLiveVideo: Bool { liveVideo.isPlaying || liveVideo.status != .disconnected }

    /// Live video from a USB UVC capture card. The most reliable Skyline
    /// video path right now — pairs with telemetry exactly like RTSP does.
    var liveCaptureCard = LiveCaptureCard()
    var isLiveCaptureCard: Bool { liveCaptureCard.isPlaying }

    // ── Live video connect / disconnect ──────────────────────────────────
    func connectVideoStream(url: String) {
        // Backdrop sources are mutually exclusive.
        if hasVideo { clearVideo() }
        if liveCaptureCard.isPlaying { liveCaptureCard.disconnect() }
        liveVideo.connect(url: url)
    }

    func disconnectVideoStream() {
        liveVideo.disconnect()
    }

    func connectCaptureCard(device: AVCaptureDevice) {
        if hasVideo { clearVideo() }
        if liveVideo.isPlaying { liveVideo.disconnect() }
        liveCaptureCard.connect(device: device)
    }

    func disconnectCaptureCard() {
        liveCaptureCard.disconnect()
    }

    // ── GPS map snapshot ─────────────────────────────────────────────────
    /// Cached MapKit render of the flight area for the GPS Map widget.
    var mapSnapshot: FlightMapImage?
    private var mapSnapshotTask: Task<Void, Never>?

    /// Native size the map is snapshotted at — 5× the widget's design size,
    /// so the widget stays crisp when a zoomed viewport pans across it.
    private static let mapSnapshotSize = CGSize(width: 1500, height: 950)

    /// Re-render the GPS map for the current track and style. Zoom is a
    /// display-only viewport transform, so it does not trigger a re-render.
    func refreshMapSnapshot() {
        mapSnapshotTask?.cancel()
        guard let log = flightLog, !log.track.isEmpty else {
            mapSnapshot = nil
            return
        }
        let track = log.track
        let style = config.mapStyle
        mapSnapshotTask = Task { @MainActor in
            let snap = await FlightMapSnapshotter.snapshot(
                track: track, style: style, size: Self.mapSnapshotSize)
            if Task.isCancelled { return }
            self.mapSnapshot = snap
        }
    }

    // ── Log loading ──────────────────────────────────────────────────────
    func loadLog(url: URL) {
        // A new log replaces any live session.
        if liveTelemetry.isConnected { liveTelemetry.disconnect() }
        mode = .logged
        do {
            let log = try FlightLog(url: url)
            flightLog = log
            logURL = url
            loadError = nil
            scrubTime = 0
            refreshMapSnapshot()
            applyMotorAutoDetect(from: log)
        } catch {
            flightLog = nil
            logURL = nil
            mapSnapshot = nil
            loadError = "Couldn't read \(url.lastPathComponent) — "
                + "the log may be truncated or from an unsupported firmware."
        }
    }

    /// On a fresh log, if the user hasn't customised the Motors widget,
    /// replace the factory-default channels with whatever the log's PARM
    /// messages say (SERVOn_FUNCTION). User edits are left alone.
    private func applyMotorAutoDetect(from log: FlightLog) {
        guard config.motorWidget.matchesFactoryDefault,
              let detected = MotorWidgetConfig.fromServoFunctions(log.servoFunctions)
        else { return }
        config.motorWidget = detected
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
        // A loaded file replaces any live backdrop.
        if liveVideo.isPlaying { liveVideo.disconnect() }
        if liveCaptureCard.isPlaying { liveCaptureCard.disconnect() }
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

    // ── Render selection ─────────────────────────────────────────────────
    /// Whether the timeline is in trim mode — when on, the scrub bar shows
    /// a draggable yellow trim frame around the selected range.
    var trimMode: Bool = false

    /// In and out points (in scrub-timeline seconds) for rendering only a
    /// slice of the overlay. Both must be set with `end > start` for the
    /// "Render Selected Range" option to be available.
    var rangeStart: Double?
    var rangeEnd: Double?

    /// A valid render range is set.
    var hasRange: Bool {
        guard let s = rangeStart, let e = rangeEnd else { return false }
        return e > s
    }

    /// Flip trim mode on/off. Turning it on initialises the range to the
    /// full timeline so the yellow frame is immediately visible — the user
    /// then drags the chevron handles inward to narrow it. Turning it off
    /// preserves the range so re-entering trim mode restores the selection.
    func toggleTrimMode() {
        if trimMode {
            trimMode = false
        } else {
            if rangeStart == nil || rangeEnd == nil ||
               rangeStart == rangeEnd {
                rangeStart = 0
                rangeEnd = max(0.001, timelineDuration)
            }
            trimMode = true
        }
    }

    func clearRange() {
        rangeStart = nil
        rangeEnd = nil
    }

    // ── Export ───────────────────────────────────────────────────────────
    enum RenderPhase: Equatable {
        case idle
        case rendering(Double)   // 0...1 progress
        case done(URL)
        case failed(String)
    }

    /// Which portion of the timeline an export covers.
    enum ExportScope { case full, range }

    var renderPhase: RenderPhase = .idle
    private var exporter: VideoExporter?

    var isRendering: Bool {
        if case .rendering = renderPhase { return true }
        return false
    }

    /// Ask for an output location, then render the overlay to a video file.
    ///
    /// `scope` selects whether the export covers the whole timeline or just
    /// the in/out range the user marked. With `.range` the output starts at
    /// `rangeStart` and lasts `rangeEnd - rangeStart` seconds.
    func startExport(scope: ExportScope = .full) {
        guard let log = flightLog else { return }

        let exportStart: Double
        let exportDuration: Double?
        let nameSuffix: String
        switch scope {
        case .range:
            guard let s = rangeStart, let e = rangeEnd, e > s else { return }
            exportStart = s
            exportDuration = e - s
            nameSuffix = String(format: "_range_%.0f-%.0fs", s, e)
        case .full:
            exportStart = 0
            exportDuration = hasVideo && videoDuration > 0 ? videoDuration : nil
            nameSuffix = "_overlay"
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.quickTimeMovie]
        let base = logURL?.deletingPathExtension().lastPathComponent ?? "overlay"
        panel.nameFieldStringValue = "\(base)\(nameSuffix).mov"
        panel.message = "Choose where to save the overlay video"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let offset = timeOffset
        let exporter = VideoExporter()
        self.exporter = exporter
        renderPhase = .rendering(0)
        Task { @MainActor in
            do {
                try await exporter.export(log: log, config: config, to: url,
                                          startTime: exportStart,
                                          duration: exportDuration,
                                          timeOffset: offset,
                                          mapSnapshot: mapSnapshot) { p in
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
