import SwiftUI

/// Transparent hit layer over the preview — selecting and dragging widgets.
/// Kept separate from `OverlayView` so the renderer stays gesture-free.
struct WidgetInteractionLayer: View {
    @Environment(AppModel.self) private var model
    var frameSize: CGSize

    /// Normalised position of the widget when the current drag began.
    @State private var dragOrigin: CGPoint?

    var body: some View {
        let layout = OverlayLayout(config: model.config, frameSize: frameSize)
        ZStack(alignment: .topLeading) {
            ForEach(WidgetKind.allCases) { kind in
                if model.config[kind].isEnabled {
                    handle(kind, rect: layout.rect(for: kind))
                }
            }
        }
        .frame(width: frameSize.width, height: frameSize.height)
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
                        let x = origin.x + value.translation.width / frameSize.width
                        let y = origin.y + value.translation.height / frameSize.height
                        model.config[kind].position = CGPoint(
                            x: min(max(x, 0), 1), y: min(max(y, 0), 1))
                    }
                    .onEnded { _ in dragOrigin = nil })
    }
}
