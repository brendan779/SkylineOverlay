import SwiftUI

/// Three-pane shell: Sidebar | (TitleBar / Preview) | Inspector.
/// Scaffold placeholders — real panes land in later steps.
struct ContentView: View {
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(Theme.border)
            VStack(spacing: 0) {
                titleBar
                Divider().overlay(Theme.border)
                HStack(spacing: 0) {
                    preview
                    Divider().overlay(Theme.border)
                    inspector
                }
            }
        }
        .background(Theme.appBackground)
        .ignoresSafeArea()
    }

    private var sidebar: some View {
        VStack {
            Text("Sidebar")
                .foregroundStyle(Theme.textMuted)
        }
        .frame(width: Theme.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(Theme.surface)
    }

    private var titleBar: some View {
        HStack {
            Text("Skyline")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: Theme.titleBarHeight)
        .background(Theme.surface)
    }

    private var preview: some View {
        VStack {
            Text("Preview")
                .foregroundStyle(Theme.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.previewBackground)
    }

    private var inspector: some View {
        VStack {
            Text("Inspector")
                .foregroundStyle(Theme.textMuted)
        }
        .frame(width: Theme.inspectorWidth)
        .frame(maxHeight: .infinity)
        .background(Theme.surface)
    }
}
