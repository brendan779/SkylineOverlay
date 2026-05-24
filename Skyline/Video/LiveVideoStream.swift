import Foundation
import Observation
import AppKit

#if canImport(VLCKit)
import VLCKit
#endif

/// Wrapper around an RTSP live source. Drives a VLC media player when the
/// `VLCKit` Swift package is available; otherwise it's a no-op stub that
/// lets the rest of the app build and lets the user wire VLCKit in later
/// without any Skyline-side code changes.
///
/// Inherits NSObject because `VLCMediaPlayerDelegate` is an Objective-C
/// protocol — required even when VLCKit isn't linked, so the class shape
/// stays consistent.
///
/// See `Skyline/Video/VIDEOKIT_SETUP.md` for the SwiftPM hookup.
@MainActor
@Observable
final class LiveVideoStream: NSObject {

    enum Status: Equatable {
        case disconnected
        case connecting(url: String)
        case playing(url: String)
        case stalled(url: String)
        case failed(String)
    }

    var status: Status = .disconnected
    var lastConnectedURL: String = ""

    /// True only when VLCKit is linked and the media is actively playing.
    var isPlaying: Bool {
        if case .playing = status { return true }
        return false
    }

#if canImport(VLCKit)
    /// The VLC media player powering playback. Configured for low-latency
    /// RTSP — the Cosmostreamer Pi feed feels near-real-time. Internal
    /// (not fileprivate) so `VLCVideoNSView` in a sibling file can attach
    /// itself as the drawable.
    let player: VLCMediaPlayer = {
        let p = VLCMediaPlayer()
        p.drawable = nil      // owned by VLCVideoNSView once attached
        return p
    }()

    override init() {
        super.init()
        player.delegate = self
    }
#else
    override init() { super.init() }
#endif

    /// Start playing the given RTSP/RTP/UDP URL. No-op when VLCKit isn't
    /// linked — `status` flips to `.failed` with a helpful message instead.
    func connect(url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lastConnectedURL = trimmed
        UserDefaults.standard.set(trimmed, forKey: "Skyline.video.url")

#if canImport(VLCKit)
        guard let mediaURL = URL(string: trimmed) else {
            status = .failed("Bad URL")
            return
        }
        let media = VLCMedia(url: mediaURL)
        media.addOptions([
            "network-caching": 200,
            "live-caching": 200,
            "rtsp-tcp": NSNull(),     // force TCP for stability
        ])
        player.media = media
        player.play()
        status = .connecting(url: trimmed)
#else
        status = .failed("RTSP playback needs the VLCKit Swift package — "
                         + "see Skyline/Video/VIDEOKIT_SETUP.md")
#endif
    }

    func disconnect() {
#if canImport(VLCKit)
        player.stop()
#endif
        status = .disconnected
    }
}

#if canImport(VLCKit)
/// VLCKit fires events from its own queue. The delegate method is therefore
/// `nonisolated`; it hops back to the main actor to publish updates.
extension LiveVideoStream: VLCMediaPlayerDelegate {
    nonisolated func mediaPlayerStateChanged(_ aNotification: Notification) {
        Task { @MainActor in self.refreshStatusFromPlayer() }
    }

    /// Read the player's current state and map it onto our public `Status`.
    /// Uses a non-frozen switch with `default:` so future VLCKit versions
    /// adding cases don't break the build.
    fileprivate func refreshStatusFromPlayer() {
        let url = lastConnectedURL
        switch player.state {
        case .playing:           status = .playing(url: url)
        case .buffering:         status = .connecting(url: url)
        case .stopped, .ended:   status = .disconnected
        case .error:             status = .failed("VLC playback error")
        case .paused:            status = .stalled(url: url)
        default:                 break    // .opening, .esAdded, etc.
        }
    }
}
#endif
