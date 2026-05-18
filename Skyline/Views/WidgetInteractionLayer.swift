import SwiftUI

/// Transparent hit layer over the preview — selecting and dragging widgets,
/// with optional snap-to-grid alignment. Kept separate from `OverlayView`
/// so the renderer stays gesture-free.
struct WidgetInteractionLayer: View {
    @Environment(AppModel.self) private var model
    var frameSize: CGSize

    /// Normalised position of the widget when the current drag began.
    @State private var dragOrigin: CGPoint?

    var body: some View {
        let layout = OverlayLayout(config: model.config, frameSize: frameSize)
        ZStack(alignment: .topLeading) {
            if model.snapToGrid, model.selectedWidget != nil {
                gridOverlay
            }
            ForEach(WidgetKind.allCases) { kind in
                if model.config[kind].isEnabled {
                    handle(kind, rect: layout.rect(for: kind))
                }
            }
        }
        .frame(width: frameSize.width, height: frameSize.height)
    }

    /// Faint grid shown while a widget is selected, so snap points are visible.
    private var gridOverlay: some View {
        Canvas { ctx, size in
            let n = max(1, model.gridDivisions)
            for i in 1..<n {
                let x = size.width * CGFloat(i) / CGFloat(n)
                let y = size.height * CGFloat(i) / CGFloat(n)
                ctx.stroke(segment(x, 0, x, size.height),
                           with: .color(.white.opacity(0.06)), lineWidth: 1)
                ctx.stroke(segment(0, y, size.width, y),
                           with: .color(.white.opacity(0.06)), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }

    private func handle(_ kind: WidgetKind, rect: CGRect) -> some View {
        let selected = model.selectedWidget == kind
        return RoundedRectangle(cornerRadius: 6)
            .fill(Color.white.opacity(0.001))   // hit-testable, invisible
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Theme.accent, lineWidth: selected ? 1.5 : 0))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .onTapGesture { model.selectedWidget = kind }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        if dragOrigin == nil {
                            dragOrigin = model.config[kind].position
                            model.selectedWidget = kind
                        }
                        guard let origin = dragOrigin else { return }
                        var x = origin.x + value.translation.width / frameSize.width
                        var y = origin.y + value.translation.height / frameSize.height
                        x = min(max(x, 0), 1)
                        y = min(max(y, 0), 1)
                        if model.snapToGrid {
                            let n = Double(max(1, model.gridDivisions))
                            x = (x * n).rounded() / n
                            y = (y * n).rounded() / n
                        }
                        model.config[kind].position = CGPoint(x: x, y: y)
                    }
                    .onEnded { _ in dragOrigin = nil })
    }
}
