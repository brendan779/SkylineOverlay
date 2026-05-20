import SwiftUI

/// Sticky bar at the foot of the Inspector — drives and reports the export.
struct RenderBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 10) {
            switch model.renderPhase {
            case .idle:                idleState
            case .rendering(let p):    renderingState(p)
            case .done(let url):       doneState(url)
            case .failed(let message): failedState(message)
            }
        }
        .padding(14)
        .background(Color.black.opacity(0.25))
        .overlay(Divider().overlay(Theme.border), alignment: .top)
    }

    private var idleState: some View {
        VStack(spacing: 4) {
            Menu {
                Button {
                    model.startExport(scope: .range)
                } label: {
                    Label(rangeMenuTitle, systemImage: "scissors")
                }
                .disabled(!model.hasRange)
            } label: {
                Text("Render Overlay")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
            } primaryAction: {
                model.startExport(scope: .full)
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.large)
            .disabled(!model.hasLog)

            if let span = rangeSpan {
                Text("Range: \(span)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
            }
        }
    }

    /// Label for the dropdown item — includes the range length when set so
    /// the user can see at a glance what "Render Selected Range" will do.
    private var rangeMenuTitle: String {
        if let span = rangeSpan {
            return "Render Selected Range (\(span))"
        }
        return "Render Selected Range"
    }

    /// Formatted duration of the marked in/out range, or nil when none.
    private var rangeSpan: String? {
        guard let s = model.rangeStart, let e = model.rangeEnd,
              e > s else { return nil }
        let secs = Int((e - s).rounded())
        return String(format: "%02d:%02d", secs / 60, secs % 60)
    }

    private func renderingState(_ progress: Double) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text("Rendering")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(Int(progress * 100)) %")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
            }
            ProgressView(value: progress)
                .tint(Theme.accent)
            HStack {
                Spacer()
                Button("Cancel") { model.cancelExport() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func doneState(_ url: URL) -> some View {
        VStack(spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.accent)
                Text("Render complete")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            HStack(spacing: 6) {
                Button("Show in Finder") { model.revealInFinder(url) }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                Button("Render Another") { model.resetRender() }
                    .buttonStyle(.bordered)
                Spacer()
            }
            .controlSize(.small)
        }
    }

    private func failedState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(Theme.errorText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Try Again") { model.resetRender() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}
