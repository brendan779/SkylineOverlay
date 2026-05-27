import SwiftUI
import AppKit
import AVFoundation

/// NSView whose backing layer IS the capture-session preview layer, so the
/// preview resizes with the view automatically (no manual layout pass).
final class CapturePreviewNSView: NSView {
    init(session: AVCaptureSession) {
        super.init(frame: .zero)
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspect
        preview.backgroundColor = NSColor.black.cgColor
        wantsLayer = true
        layer = preview
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }
}

/// SwiftUI wrapper around the capture preview layer. The HUD `OverlayView`
/// composites on top in `PreviewPane`'s ZStack, same as for the video file
/// path.
struct CaptureCardNSView: NSViewRepresentable {
    let captureCard: LiveCaptureCard

    func makeNSView(context: Context) -> NSView {
        CapturePreviewNSView(session: captureCard.session)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Layer-backed view resizes automatically; nothing per-frame to do.
    }
}
