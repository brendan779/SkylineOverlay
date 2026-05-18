import SwiftUI

/// Right pane — header chrome wrapping the scrollable overlay controls.
struct InspectorView: View {
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

            ScrollView {
                InspectorControls().padding(18)
            }

            RenderBar()
        }
        .frame(width: Theme.inspectorWidth)
        .frame(maxHeight: .infinity)
        .background(Theme.surface)
    }
}

/// Overlay controls bound to `OverlayConfig`: per-widget enable / scale /
/// opacity / position / colour, plus global output settings.
struct InspectorControls: View {
    @Environment(AppModel.self) private var model

    private let resolutions: [(w: Int, h: Int, label: String)] = [
        (3840, 2160, "3840 × 2160"),
        (2560, 1440, "2560 × 1440"),
        (1920, 1080, "1920 × 1080"),
        (1280, 720,  "1280 × 720"),
    ]
    private let frameRates: [Double] = [24, 25, 30, 50, 60]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            widgetsSection
            if let kind = model.selectedWidget {
                widgetEditor(kind)
            }
            outputSection
        }
    }

    // ── Widget list ──────────────────────────────────────────────────────
    private var widgetsSection: some View {
        section("Widgets") {
            VStack(spacing: 1) {
                ForEach(WidgetKind.allCases) { widgetRow($0) }
            }
        }
    }

    private func widgetRow(_ kind: WidgetKind) -> some View {
        let selected = model.selectedWidget == kind
        return HStack(spacing: 9) {
            Toggle("", isOn: binding(kind).isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
            Text(kind.displayName)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 10))
                .foregroundStyle(selected ? Theme.accent : Theme.textMuted)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6)
            .fill(selected ? Theme.accent.opacity(0.12) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { model.selectedWidget = selected ? nil : kind }
    }

    // ── Per-widget editor ────────────────────────────────────────────────
    private func widgetEditor(_ kind: WidgetKind) -> some View {
        let w = binding(kind)
        return section(kind.displayName) {
            VStack(alignment: .leading, spacing: 12) {
                sliderRow("Scale", w.scale,
                          range: WidgetSettings.scaleRange, format: "%.2f×")
                sliderRow("Opacity", w.opacity, range: 0...1, format: "%.0f%%",
                          display: { $0 * 100 })
                sliderRow("Position X", positionX(kind), range: 0...1, format: "%.2f")
                sliderRow("Position Y", positionY(kind), range: 0...1, format: "%.2f")
                colorRow("Accent", accentColor(kind))
                colorRow("Background", backgroundColor(kind))
            }
        }
    }

    // ── Output ───────────────────────────────────────────────────────────
    private var outputSection: some View {
        @Bindable var config = model.config
        return section("Output") {
            VStack(alignment: .leading, spacing: 10) {
                pickerRow("Speed units", selection: $config.speedUnits) {
                    ForEach(SpeedUnit.allCases) { Text($0.label).tag($0) }
                }
                pickerRow("Altitude", selection: $config.altitudeDatum) {
                    ForEach(AltitudeDatum.allCases) { Text($0.label).tag($0) }
                }
                pickerRow("Resolution", selection: resolutionIndex) {
                    ForEach(resolutions.indices, id: \.self) {
                        Text(resolutions[$0].label).tag($0)
                    }
                }
                pickerRow("Frame rate", selection: $config.output.fps) {
                    ForEach(frameRates, id: \.self) {
                        Text(String(format: "%.0f", $0)).tag($0)
                    }
                }
                pickerRow("Codec", selection: $config.output.codec) {
                    ForEach(VideoCodec.allCases) { Text($0.label).tag($0) }
                }
            }
        }
    }

    // ── Bindings ─────────────────────────────────────────────────────────
    private func binding(_ kind: WidgetKind) -> Binding<WidgetSettings> {
        Binding { model.config[kind] } set: { model.config[kind] = $0 }
    }
    private func positionX(_ kind: WidgetKind) -> Binding<Double> {
        Binding { model.config[kind].position.x }
            set: { model.config[kind].position.x = $0 }
    }
    private func positionY(_ kind: WidgetKind) -> Binding<Double> {
        Binding { model.config[kind].position.y }
            set: { model.config[kind].position.y = $0 }
    }
    private func accentColor(_ kind: WidgetKind) -> Binding<Color> {
        Binding { model.config[kind].accent.color }
            set: { model.config[kind].accent = RGBAColor($0) }
    }
    private func backgroundColor(_ kind: WidgetKind) -> Binding<Color> {
        Binding { model.config[kind].background.color }
            set: { model.config[kind].background = RGBAColor($0) }
    }
    private var resolutionIndex: Binding<Int> {
        Binding {
            resolutions.firstIndex { $0.w == model.config.output.width
                && $0.h == model.config.output.height } ?? 2
        } set: {
            model.config.output.width = resolutions[$0].w
            model.config.output.height = resolutions[$0].h
        }
    }

    // ── Reusable rows ────────────────────────────────────────────────────
    private func section<Content: View>(
        _ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Theme.textMuted)
            content()
        }
    }

    private func sliderRow(_ label: String, _ value: Binding<Double>,
                           range: ClosedRange<Double>, format: String,
                           display: @escaping (Double) -> Double = { $0 })
        -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(String(format: format, display(value.wrappedValue)))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
            }
            Slider(value: value, in: range).controlSize(.mini)
        }
    }

    private func colorRow(_ label: String, _ color: Binding<Color>) -> some View {
        ColorPicker(selection: color, supportsOpacity: true) {
            Text(label).font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func pickerRow<S: Hashable, Content: View>(
        _ label: String, selection: Binding<S>,
        @ViewBuilder _ content: () -> Content) -> some View {
        HStack {
            Text(label).font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Picker("", selection: selection) { content() }
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
        }
    }
}
