import SwiftUI
import AVFoundation
import AppKit

/// Displays an `AVPlayer`'s video as a plain layer — no transport controls,
/// so the overlay and scrub bar drive playback. Used as the preview backdrop.
struct PlayerView: NSViewRepresentable {
    var player: AVPlayer

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = NSColor.black.cgColor
        view.layer = layer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let layer = nsView.layer as? AVPlayerLayer else { return }
        if layer.player !== player {
            layer.player = player
        }
    }
}
