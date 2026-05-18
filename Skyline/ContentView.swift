import SwiftUI

/// Three-pane window: Sidebar | (TitleBar / Preview) | Inspector.
struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
            Divider().overlay(Theme.border)
            VStack(spacing: 0) {
                titleBar
                Divider().overlay(Theme.border)
                HStack(spacing: 0) {
                    PreviewPane()
                    Divider().overlay(Theme.border)
                    InspectorView()
                }
            }
        }
        .background(Theme.appBackground)
        .ignoresSafeArea()
    }

    private var titleBar: some View {
        HStack(spacing: 8) {
            Text(model.logURL?.lastPathComponent ?? "Skyline")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(model.hasLog ? Theme.textPrimary : Theme.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: Theme.titleBarHeight)
        .background(
            LinearGradient(colors: [Color(hex: 0x1C1F24), Color(hex: 0x181B1F)],
                           startPoint: .top, endPoint: .bottom))
    }
}
