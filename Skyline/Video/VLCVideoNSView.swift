import SwiftUI
import AppKit

#if canImport(VLCKit)
import VLCKit
#endif

/// SwiftUI wrapper around VLC's video drawable. When VLCKit is linked the
/// view becomes the player's render target; otherwise it shows a
/// placeholder with setup instructions.
struct VLCVideoNSView: NSViewRepresentable {
    let stream: LiveVideoStream

    func makeNSView(context: Context) -> NSView {
#if canImport(VLCKit)
        let host = NSView(frame: .zero)
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.black.cgColor
        stream.player.drawable = host
        return host
#else
        let host = NSView(frame: .zero)
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.black.cgColor
        let label = NSTextField(labelWithString:
            "Live RTSP playback needs VLCKit.\n"
            + "See Skyline/Video/VIDEOKIT_SETUP.md.")
        label.alignment = .center
        label.textColor = NSColor.secondaryLabelColor
        label.font = NSFont.systemFont(ofSize: 12)
        label.maximumNumberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: host.centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualTo: host.widthAnchor,
                                         constant: -40),
        ])
        return host
#endif
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // VLC keeps its own pacing — nothing per-frame for us to do.
    }
}
