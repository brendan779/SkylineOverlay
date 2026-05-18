import SwiftUI

/// Placeholder for the source video frame — diagonal stripes with a caption.
/// Replaced by the real decoded frame once video import lands.
struct VideoBackdrop: View {
    var caption: String = "FLIGHT FOOTAGE PREVIEW"

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .color(Color(white: 0.07)))
            let stripe: CGFloat = 28
            var x: CGFloat = -size.height
            while x < size.width {
                var p = Path()
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x + size.height, y: size.height))
                p.addLine(to: CGPoint(x: x + size.height + stripe, y: size.height))
                p.addLine(to: CGPoint(x: x + stripe, y: 0))
                p.closeSubpath()
                ctx.fill(p, with: .color(Color(white: 0.10)))
                x += stripe * 2
            }
        }
        .overlay(
            Text(caption)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.28))
        )
    }
}
