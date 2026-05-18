import SwiftUI

/// Left pane — brand, the open-log action, and the loaded flight.
struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: Theme.titleBarHeight)   // traffic-light row

            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(colors: [Theme.accent, Theme.accent.opacity(0.5)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 22, height: 22)
                    .overlay(Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.black))
                Text("Skyline")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("BETA")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 3)
                        .stroke(Theme.borderStrong, lineWidth: 0.5))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Button {
                model.presentOpenPanel()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                    Text("Open Flight Log").font(.system(size: 12))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderStrong, lineWidth: 0.5))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.bottom, 14)

            sectionHeader("Flights")
            if let url = model.logURL {
                fileRow(name: url.lastPathComponent)
            } else {
                Text("No log loaded")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, 18).padding(.top, 2)
            }

            Spacer()
        }
        .frame(width: Theme.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(Theme.surface)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Theme.textMuted)
            .padding(.horizontal, 18)
            .padding(.bottom, 6)
    }

    private func fileRow(name: String) -> some View {
        HStack(spacing: 9) {
            Text("BIN")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(Theme.accent)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 5).fill(Theme.accent.opacity(0.13)))
            Text(name)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1).truncationMode(.middle)
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.07)))
        .padding(.horizontal, 8)
    }
}
