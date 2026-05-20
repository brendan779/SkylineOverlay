import SwiftUI

extension Array {
    /// Bounds-checked element access — `nil` when the index is out of range.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

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
            syncSection
            outputSection
        }
    }

    // ── Sync ─────────────────────────────────────────────────────────────
    private var syncSection: some View {
        section("Sync") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Telemetry offset")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(String(format: "%+.1f s", model.timeOffset))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textMuted)
                }
                Slider(value: offsetBinding, in: -30...30)
                    .controlSize(.mini)
                HStack(spacing: 8) {
                    Stepper("", value: offsetBinding, in: -600...600, step: 0.1)
                        .labelsHidden()
                    Text("Nudge ±0.1 s to sync the overlay to the video")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textMuted)
                    Spacer()
                }
            }
        }
    }

    private var offsetBinding: Binding<Double> {
        Binding { model.timeOffset } set: { model.timeOffset = $0 }
    }

    // ── Widget list ──────────────────────────────────────────────────────
    private var widgetsSection: some View {
        section("Widgets") {
            VStack(spacing: 8) {
                Toggle(isOn: Binding { model.snapToGrid }
                    set: { model.snapToGrid = $0 }) {
                    Text("Snap to grid")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)

                VStack(spacing: 1) {
                    ForEach(WidgetKind.allCases) { widgetRow($0) }
                }
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
        return VStack(alignment: .leading, spacing: 20) {
            section(kind.displayName) {
                VStack(alignment: .leading, spacing: 12) {
                    sliderRow("Scale", w.scale,
                              range: WidgetSettings.scaleRange, format: "%.2f×")
                    sliderRow("Opacity", w.opacity, range: 0...1, format: "%.0f%%",
                              display: { $0 * 100 })
                    sliderRow("Position X", positionX(kind), range: 0...1,
                              format: "%.2f")
                    sliderRow("Position Y", positionY(kind), range: 0...1,
                              format: "%.2f")
                    colorRow("Accent", accentColor(kind))
                    colorRow("Background", backgroundColor(kind))
                    widgetExtras(kind)
                }
            }
            if kind.supportsThreshold {
                thresholdSection(kind)
            }
        }
    }

    // ── Threshold editor ─────────────────────────────────────────────────
    private func thresholdSection(_ kind: WidgetKind) -> some View {
        let profile = model.config.threshold(for: kind)
        return section("Threshold Colours") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: thresholdEnabled(kind)) {
                    Text("Colour by value")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)

                if profile.isEnabled {
                    let presets = ThresholdProfile.presets(for: kind)
                    if !presets.isEmpty {
                        Menu("Load preset…") {
                            ForEach(presets.indices, id: \.self) { i in
                                Button(presets[i].name) {
                                    var p = presets[i].profile
                                    p.isEnabled = true
                                    model.config.thresholds[kind] = p
                                }
                            }
                        }
                        .controlSize(.small)
                        .fixedSize()
                    }
                    ForEach(profile.stops.indices, id: \.self) {
                        thresholdStopRow(kind, index: $0)
                    }
                    Button { addThresholdStop(kind) } label: {
                        Label("Add stop", systemImage: "plus")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private func thresholdStopRow(_ kind: WidgetKind, index: Int) -> some View {
        let value = model.config.threshold(for: kind).stops[safe: index]?.value ?? 0
        return HStack(spacing: 6) {
            ColorPicker("", selection: stopColor(kind, index),
                        supportsOpacity: true)
                .labelsHidden()
            Text(String(format: "%.2f", value))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
                .frame(width: 48, alignment: .leading)
            Stepper("", value: stopValue(kind, index), step: kind.thresholdStep)
                .labelsHidden()
            Spacer()
            Button { removeThresholdStop(kind, index) } label: {
                Image(systemName: "minus.circle").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textMuted)
        }
    }

    // ── Threshold bindings + mutations ───────────────────────────────────
    private func thresholdEnabled(_ kind: WidgetKind) -> Binding<Bool> {
        Binding {
            model.config.threshold(for: kind).isEnabled
        } set: { on in
            var p = model.config.threshold(for: kind)
            p.isEnabled = on
            // First time on with no stops: seed from the default preset.
            if on, p.stops.isEmpty,
               let preset = ThresholdProfile.presets(for: kind).first {
                p = preset.profile
                p.isEnabled = true
            }
            model.config.thresholds[kind] = p
        }
    }

    private func stopValue(_ kind: WidgetKind, _ i: Int) -> Binding<Double> {
        Binding {
            model.config.threshold(for: kind).stops[safe: i]?.value ?? 0
        } set: { v in
            var p = model.config.threshold(for: kind)
            guard i < p.stops.count else { return }
            p.stops[i].value = v
            model.config.thresholds[kind] = p
        }
    }

    private func stopColor(_ kind: WidgetKind, _ i: Int) -> Binding<Color> {
        Binding {
            model.config.threshold(for: kind).stops[safe: i]?.color.color ?? .white
        } set: { c in
            var p = model.config.threshold(for: kind)
            guard i < p.stops.count else { return }
            p.stops[i].color = RGBAColor(c)
            model.config.thresholds[kind] = p
        }
    }

    private func addThresholdStop(_ kind: WidgetKind) {
        var p = model.config.threshold(for: kind)
        let next = (p.stops.map(\.value).max() ?? 0) + kind.thresholdStep
        p.stops.append(ThresholdStop(value: next, color: .white))
        model.config.thresholds[kind] = p
    }

    private func removeThresholdStop(_ kind: WidgetKind, _ i: Int) {
        var p = model.config.threshold(for: kind)
        guard i < p.stops.count else { return }
        p.stops.remove(at: i)
        model.config.thresholds[kind] = p
    }

    /// Per-widget controls that only some widget kinds need.
    @ViewBuilder
    private func widgetExtras(_ kind: WidgetKind) -> some View {
        switch kind {
        case .battery:
            sliderRow("Pack capacity", batteryCapacity,
                      range: 500...20000, format: "%.0f mAh")
        case .gforce:
            pickerRow("Max scale", selection: gForceScale) {
                ForEach([2.0, 4.0, 6.0, 8.0], id: \.self) {
                    Text(String(format: "±%.0f g", $0)).tag($0)
                }
            }
        case .distance:
            pickerRow("Units", selection: distanceUnits) {
                ForEach(DistanceUnit.allCases) { Text($0.label).tag($0) }
            }
            Toggle(isOn: showMaxDistance) {
                Text("Show max reached")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
        case .map:
            pickerRow("Map style", selection: mapStyle) {
                ForEach(FlightMapStyle.allCases) { Text($0.label).tag($0) }
            }
            sliderRow("Zoom", mapZoom, range: 1...6, format: "%.1f×")
            sliderRow("Trail", mapTrailSeconds, range: 0...120) {
                $0 < 1 ? "Full path" : String(format: "%.0f s", $0)
            }
        case .groundSpeed, .altitude:
            smoothingControls(kind, allowsKalman: true)
        case .airSpeed:
            smoothingControls(kind, allowsKalman: false)
        case .motors:
            motorChannelEditor
        default:
            EmptyView()
        }
    }

    // ── Motors widget — channel editor ───────────────────────────────────
    private var motorChannelEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(model.config.motorWidget.channels.indices, id: \.self) {
                motorChannelRow(index: $0)
            }

            HStack(spacing: 6) {
                Button { addMotorChannel() } label: {
                    Label("Add channel", systemImage: "plus")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)

                Spacer()

                if let detected = MotorWidgetConfig.fromServoFunctions(
                        model.flightLog?.servoFunctions ?? [:]) {
                    Button { model.config.motorWidget = detected } label: {
                        Text("Auto-detect")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textSecondary)
                    .help("Restore channels from this log's SERVO_FUNCTION parameters")
                }
            }
        }
    }

    private func motorChannelRow(index i: Int) -> some View {
        let value = model.config.motorWidget.channels[safe: i]
        let canRemove = model.config.motorWidget.channels.count > 1
        return HStack(spacing: 6) {
            TextField("Label", text: motorLabelBinding(i))
                .textFieldStyle(.roundedBorder)
                .controlSize(.mini)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 56)
            Text("C\(value?.channel ?? 0)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 30, alignment: .leading)
            Stepper(value: motorChannelBinding(i), in: 1...16) {
                EmptyView()
            }
            .labelsHidden()
            .controlSize(.mini)
            Spacer()
            Button { removeMotorChannel(i) } label: {
                Image(systemName: "minus.circle").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(canRemove ? Theme.textMuted
                                       : Theme.textMuted.opacity(0.3))
            .disabled(!canRemove)
        }
    }

    private func motorLabelBinding(_ i: Int) -> Binding<String> {
        Binding {
            model.config.motorWidget.channels[safe: i]?.label ?? ""
        } set: { v in
            guard i < model.config.motorWidget.channels.count else { return }
            model.config.motorWidget.channels[i].label = v
        }
    }

    private func motorChannelBinding(_ i: Int) -> Binding<Int> {
        Binding {
            model.config.motorWidget.channels[safe: i]?.channel ?? 1
        } set: { v in
            guard i < model.config.motorWidget.channels.count else { return }
            model.config.motorWidget.channels[i].channel = v
        }
    }

    private func addMotorChannel() {
        let used = Set(model.config.motorWidget.channels.map(\.channel))
        let nextChannel = (1...16).first { !used.contains($0) } ?? 1
        let nextLabel = "M\(model.config.motorWidget.channels.count + 1)"
        model.config.motorWidget.channels.append(
            MotorChannelEntry(channel: nextChannel, label: nextLabel))
    }

    private func removeMotorChannel(_ i: Int) {
        guard i < model.config.motorWidget.channels.count,
              model.config.motorWidget.channels.count > 1 else { return }
        model.config.motorWidget.channels.remove(at: i)
    }

    /// Moving-average window slider, plus an optional Kalman toggle.
    @ViewBuilder
    private func smoothingControls(_ kind: WidgetKind,
                                   allowsKalman: Bool) -> some View {
        let useKalman = model.config.smoothing(for: kind).useKalman
        if allowsKalman {
            Toggle(isOn: smoothingKalman(kind)) {
                Text("Kalman filter")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        if !useKalman {
            sliderRow("Smoothing", smoothingWindow(kind), range: 0...5) {
                $0 < 0.05 ? "Off" : String(format: "%.1f s", $0)
            }
        }
    }

    private func smoothingWindow(_ kind: WidgetKind) -> Binding<Double> {
        Binding {
            model.config.smoothing(for: kind).window
        } set: { v in
            var s = model.config.smoothing(for: kind)
            s.window = v
            model.config.smoothing[kind] = s
        }
    }
    private func smoothingKalman(_ kind: WidgetKind) -> Binding<Bool> {
        Binding {
            model.config.smoothing(for: kind).useKalman
        } set: { on in
            var s = model.config.smoothing(for: kind)
            s.useKalman = on
            model.config.smoothing[kind] = s
        }
    }

    private var batteryCapacity: Binding<Double> {
        Binding { model.config.batteryCapacity }
            set: { model.config.batteryCapacity = $0 }
    }
    private var gForceScale: Binding<Double> {
        Binding { model.config.gForceScale }
            set: { model.config.gForceScale = $0 }
    }
    private var distanceUnits: Binding<DistanceUnit> {
        Binding { model.config.distanceUnits }
            set: { model.config.distanceUnits = $0 }
    }
    private var showMaxDistance: Binding<Bool> {
        Binding { model.config.showMaxDistance }
            set: { model.config.showMaxDistance = $0 }
    }
    private var mapStyle: Binding<FlightMapStyle> {
        Binding { model.config.mapStyle }
            set: { model.config.mapStyle = $0; model.refreshMapSnapshot() }
    }
    private var mapZoom: Binding<Double> {
        Binding { model.config.mapZoom }
            set: { model.config.mapZoom = $0 }
    }
    private var mapTrailSeconds: Binding<Double> {
        Binding { model.config.mapTrailSeconds }
            set: { model.config.mapTrailSeconds = $0 }
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

    private func sliderRow(_ label: String, _ value: Binding<Double>,
                           range: ClosedRange<Double>,
                           text: @escaping (Double) -> String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(text(value.wrappedValue))
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
