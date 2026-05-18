import SwiftUI

/// Right pane — overlay controls. Fleshed out in Stage 4c.
struct InspectorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Inspector")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 18)
            .frame(height: Theme.titleBarHeight)

            Divider().overlay(Theme.border)
            Spacer()
        }
        .frame(width: Theme.inspectorWidth)
        .frame(maxHeight: .infinity)
        .background(Theme.surface)
    }
}
