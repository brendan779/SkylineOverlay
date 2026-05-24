import Foundation
import Observation
import CoreLocation

/// Picks a sensible MAVLink stream rate for the kind of telemetry link in
/// use, or opts Skyline out of managing rates entirely.
///
/// - `lora` — low-bandwidth radios (Microair LoRa, ELRS MAVLink backpacks).
/// - `sik`  — comfortable-bandwidth radios (SiK, RFD900).
/// - `custom` — Skyline does not send `REQUEST_DATA_STREAM`; whatever the
///   FC's `SR_*` parameters give is what you get.
enum TelemetryLinkProfile: String, CaseIterable, Codable, Identifiable {
    case lora
    case sik
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lora:   return "LoRa / ELRS  (low rate, 2 Hz)"
        case .sik:    return "SiK / RFD900 (high rate, 10 Hz)"
        case .custom: return "Custom  (use FC's SR_ rates)"
        }
    }

    /// Per-stream rate sent in `REQUEST_DATA_STREAM(stream_id=ALL, rate=…)`.
    var rateHz: UInt16 {
        switch self {
        case .lora:   return 2
        case .sik:    return 10
        case .custom: return 0       // unused — see `managesRates`
        }
    }

    /// Whether Skyline should send `REQUEST_DATA_STREAM` to throttle. False
    /// for `.custom` — the FC's own settings apply.
    var managesRates: Bool { self != .custom }
}

/// Live MAVLink telemetry coming over a USB-serial radio.
///
/// Holds the latest values for every field the HUD draws, plus the
/// connection lifecycle. Builds a `TelemetrySample` on demand, mirroring
/// how `FlightLog` feeds the renderer — so widgets work identically in
/// logged and live modes.
@MainActor
@Observable
final class LiveTelemetry {

    // ── Connection state ────────────────────────────────────────────────
    enum Status: Equatable {
        case disconnected
        case connecting(port: String)
        case connected(port: String, baud: Int)
        case failed(String)
    }

    var status: Status = .disconnected
    /// Wall-clock instant of the most recent valid frame, for UI staleness.
    var lastFrameAt: Date?
    /// Frames decoded since connection opened — used as a liveness counter.
    var frameCount: Int = 0
    /// RSSI from `RC_CHANNELS`, when available (0..255).
    var rssi: UInt8 = 0

    var isConnected: Bool {
        if case .connected = status { return true }
        return false
    }

    // ── Latest values (everything the HUD reads) ────────────────────────
    private(set) var groundSpeed: Double = 0
    private(set) var airSpeed: Double = 0
    private(set) var altitudeAGL: Double = 0
    private(set) var altitudeAMSL: Double = 0
    private(set) var verticalSpeed: Double = 0
    private(set) var pitch: Double = 0
    private(set) var roll: Double = 0
    private(set) var yaw: Double = 0
    private(set) var mode: String = "—"

    private(set) var batteryVoltage: Double = 0
    private(set) var batteryCurrent: Double = 0
    private(set) var batteryConsumed: Double = 0
    private(set) var hasBattery: Bool = false

    private(set) var coordinate: GeoPoint?
    private(set) var home: GeoPoint?
    private(set) var track: [TrackPoint] = []
    private(set) var maxDistanceFromHome: Double = 0

    private(set) var windDirection: Double = 0
    private(set) var windSpeed: Double = 0
    private(set) var hasWind: Bool = false

    /// Body-frame specific force in m/s², for the g-force widget.
    private(set) var accelX: Double = 0
    private(set) var accelY: Double = 0
    private(set) var accelZ: Double = 0
    private(set) var peakLateralG: Double = 0
    private(set) var hasIMU: Bool = false

    private(set) var rcInChannels: [Int: Double] = [:]
    private(set) var rcOutChannels: [Int: Double] = [:]

    private(set) var messages: [(t: Double, text: String, severity: Int)] = []

    // ── Headtracker suppression state (live equivalent of FlightLog's
    //     precomputed timeline) ────────────────────────────────────────
    /// Whether the configured headtracker channel was last seen *outside*
    /// the centre band.
    private var headtrackerActive: Bool = false
    /// Monotonic clock instant of the most recent active/inactive flip.
    private var lastHeadtrackerFlipAt: Date = Date()

    // ── Internals ───────────────────────────────────────────────────────
    private var serial: Serial?
    private var startedAt: Date?
    private var readTask: Task<Void, Never>?
    private var parseBuffer: [UInt8] = []
    private var outboundSeq: UInt8 = 0
    /// The first sysid we hear back from on the link (typically 1).
    /// Used as the target for outbound throttling requests.
    private var fcSysId: UInt8?
    private var lastStreamRequest: Date?

    /// Our (GCS) identity. Conventional values for a desktop GCS.
    private let gcsSysId: UInt8 = 255
    private let gcsCompId: UInt8 = 0

    /// Selected link profile. Drives the cap sent in `REQUEST_DATA_STREAM`
    /// — LoRa-class links need 2 Hz to stay comfortable; SiK / RFD900
    /// handle 10 Hz easily. Changing it mid-session re-requests rates.
    var linkProfile: TelemetryLinkProfile = .lora {
        didSet {
            if oldValue != linkProfile { requestThrottledStreams() }
        }
    }

    /// Seconds since the connection opened — used as `t` for messages /
    /// rangefinder fades / etc. Always non-negative.
    var sessionTime: Double {
        guard let started = startedAt else { return 0 }
        return max(0, Date().timeIntervalSince(started))
    }

    // ── Connect / disconnect ────────────────────────────────────────────

    func connect(port: String, baud: Int) {
        disconnect()                 // tear down any prior session
        let radio = Serial(path: port)
        serial = radio
        status = .connecting(port: port)
        startedAt = Date()
        frameCount = 0
        track.removeAll(keepingCapacity: true)
        messages.removeAll(keepingCapacity: true)
        rcInChannels.removeAll(); rcOutChannels.removeAll()
        peakLateralG = 0
        maxDistanceFromHome = 0
        hasBattery = false; hasIMU = false; hasWind = false
        coordinate = nil; home = nil

        do {
            let stream = try radio.open(baud: baud)
            status = .connected(port: port, baud: baud)
            readTask = Task { [weak self] in
                for await chunk in stream {
                    self?.feed(chunk)
                }
                self?.handleStreamEnd()
            }
        } catch {
            status = .failed(error.localizedDescription)
            serial = nil
            startedAt = nil
        }
    }

    func disconnect() {
        readTask?.cancel()
        readTask = nil
        serial?.close()
        serial = nil
        startedAt = nil
        parseBuffer.removeAll(keepingCapacity: true)
        fcSysId = nil
        lastStreamRequest = nil
        outboundSeq = 0
        status = .disconnected
    }

    /// Send a single `REQUEST_DATA_STREAM` that caps every stream on the
    /// FC at the link profile's rate. The FC's `SR_*` parameters set
    /// defaults at boot; this request overrides them at runtime for the
    /// link we're connected on, which is what we want.
    ///
    /// No-op when the user has chosen the `.custom` profile — in that
    /// case Skyline keeps its hands off and the FC's own `SR_*` rates
    /// apply. (If a prior session set a throttle, that lingers on the
    /// FC until reboot.)
    private func requestThrottledStreams() {
        guard linkProfile.managesRates else { return }
        guard let serial, let target = fcSysId else { return }
        let payload = Mavlink.requestDataStreamPayload(
            targetSystem: target,
            targetComponent: 1,            // MAV_COMP_ID_AUTOPILOT1
            streamId: 0,                   // MAV_DATA_STREAM_ALL
            rateHz: linkProfile.rateHz,
            start: true)
        outboundSeq = outboundSeq &+ 1
        let frame = Mavlink.encodeV1(seq: outboundSeq,
                                     sysId: gcsSysId,
                                     compId: gcsCompId,
                                     msgId: 66,    // REQUEST_DATA_STREAM
                                     payload: payload)
        serial.write(frame)
        lastStreamRequest = Date()
    }

    private func handleStreamEnd() {
        // The serial stream closed — radio unplugged or read error.
        serial = nil
        readTask = nil
        if case .connected = status {
            status = .failed("Telemetry radio disconnected")
        }
    }

    // ── Frame dispatch ──────────────────────────────────────────────────
    private func feed(_ chunk: Data) {
        parseBuffer.append(contentsOf: chunk)
        // Cap the parse buffer so a runaway feed can't OOM us.
        if parseBuffer.count > 16_384 {
            parseBuffer.removeFirst(parseBuffer.count - 16_384)
        }
        let frames = Mavlink.parse(&parseBuffer)
        for frame in frames {
            apply(frame)
            frameCount += 1
            lastFrameAt = Date()
        }
    }

    private func apply(_ frame: Mavlink.Frame) {
        // Latch the FC's sysid the first time we see it talk, and use
        // that to ask for low stream rates. Re-ask occasionally in case
        // the FC reboots or the radio loses our earlier request.
        if frame.sysId != gcsSysId, frame.sysId != 0 {
            if fcSysId != frame.sysId {
                fcSysId = frame.sysId
                requestThrottledStreams()
            } else if let last = lastStreamRequest,
                      Date().timeIntervalSince(last) > 15 {
                requestThrottledStreams()
            }
        }

        guard let id = Mavlink.MsgID(rawValue: frame.msgId) else { return }
        let p = frame.payload
        switch id {
        case .heartbeat:
            let h = Mavlink.Heartbeat(p)
            mode = Self.modeName(custom: h.customMode, baseMode: h.baseMode)
        case .sysStatus:
            let s = Mavlink.SysStatus(p)
            if s.voltageBattery > 0 { batteryVoltage = Double(s.voltageBattery) / 1000 }
            if s.currentBattery >= 0 { batteryCurrent = Double(s.currentBattery) / 100 }
            hasBattery = hasBattery || s.voltageBattery > 0
        case .gpsRawInt:
            let g = Mavlink.GpsRawInt(p)
            if g.fixType >= 2, abs(g.lat) > 1 || abs(g.lon) > 1 {
                updatePosition(lat: Double(g.lat) / 1e7,
                               lon: Double(g.lon) / 1e7,
                               altMm: g.alt, isAbs: true, relMm: nil)
            }
        case .scaledImu:
            let imu = Mavlink.ScaledImu(p)
            // SCALED_IMU reports mG — convert to m/s² for parity with HIGHRES.
            updateIMU(x: Double(imu.xacc) * 9.80665 / 1000,
                      y: Double(imu.yacc) * 9.80665 / 1000,
                      z: Double(imu.zacc) * 9.80665 / 1000)
        case .attitude:
            let a = Mavlink.Attitude(p)
            roll = Double(a.roll) * 180 / .pi
            pitch = Double(a.pitch) * 180 / .pi
            var degYaw = Double(a.yaw) * 180 / .pi
                .truncatingRemainder(dividingBy: 360)
            if degYaw < 0 { degYaw += 360 }
            yaw = degYaw
        case .globalPositionInt:
            let g = Mavlink.GlobalPositionInt(p)
            if abs(g.lat) > 1 || abs(g.lon) > 1 {
                updatePosition(lat: Double(g.lat) / 1e7,
                               lon: Double(g.lon) / 1e7,
                               altMm: g.alt, isAbs: true,
                               relMm: g.relativeAlt)
            }
            // Vertical speed: vz is cm/s, positive down — flip sign.
            verticalSpeed = -Double(g.vz) / 100
        case .servoOutputRaw:
            let s = Mavlink.ServoOutputRaw(p)
            for (i, pwm) in s.servos.enumerated() where pwm > 0 {
                rcOutChannels[i + 1] = Double(pwm)
            }
        case .rcChannels:
            let r = Mavlink.RcChannels(p)
            rssi = r.rssi
            for (i, pwm) in r.channels.enumerated() where pwm > 0 && pwm < 0xFFFF {
                rcInChannels[i + 1] = Double(pwm)
            }
        case .vfrHud:
            let h = Mavlink.VfrHud(p)
            airSpeed = Double(h.airspeed)
            groundSpeed = Double(h.groundspeed)
            altitudeAGL = Double(h.alt)         // VFR_HUD alt is AGL on ArduPilot
            verticalSpeed = Double(h.climb)
        case .highresImu:
            let imu = Mavlink.HighresImu(p)
            updateIMU(x: Double(imu.xacc), y: Double(imu.yacc), z: Double(imu.zacc))
        case .batteryStatus:
            let b = Mavlink.BatteryStatus(p)
            let v = b.packVoltage
            if v > 0 { batteryVoltage = v }
            if b.currentBattery >= 0 { batteryCurrent = Double(b.currentBattery) / 100 }
            if b.currentConsumed >= 0 { batteryConsumed = Double(b.currentConsumed) }
            hasBattery = true
        case .wind:
            let w = Mavlink.Wind(p)
            windDirection = Double(w.direction)
            windSpeed = Double(w.speed)
            hasWind = windSpeed >= 0.5
        case .homePosition:
            let h = Mavlink.HomePosition(p)
            home = GeoPoint(latitude: Double(h.latitude) / 1e7,
                            longitude: Double(h.longitude) / 1e7)
        case .statustext:
            let s = Mavlink.StatusText(p)
            messages.append((t: sessionTime, text: s.text,
                             severity: Int(s.severity)))
            // Cap the log to a reasonable rolling window.
            if messages.count > 64 { messages.removeFirst(messages.count - 64) }
        }
    }

    private func updatePosition(lat: Double, lon: Double,
                                altMm: Int32, isAbs: Bool, relMm: Int32?) {
        let p = GeoPoint(latitude: lat, longitude: lon)
        coordinate = p
        if isAbs { altitudeAMSL = Double(altMm) / 1000 }
        if let r = relMm { altitudeAGL = Double(r) / 1000 }
        if home == nil { home = p }
        track.append(TrackPoint(t: sessionTime, point: p))
        if let home {
            maxDistanceFromHome = max(maxDistanceFromHome, home.distance(to: p))
        }
        // Keep the live track bounded so a long session doesn't grow forever.
        if track.count > 20_000 { track.removeFirst(track.count - 20_000) }
    }

    private func updateIMU(x: Double, y: Double, z: Double) {
        accelX = x; accelY = y; accelZ = z
        hasIMU = true
        let g = FlightLog.standardGravity
        let lateral = sqrt(x * x + y * y) / g
        peakLateralG = max(peakLateralG, lateral)
    }

    // ── Build a TelemetrySample for the renderer ────────────────────────
    /// Build a snapshot for the HUD using the latest values plus the
    /// motor / threshold / headtracker config the user has set.
    func currentSample(config: OverlayConfig) -> TelemetrySample {
        let t = sessionTime
        let useAbs = config.altitudeDatum == .absolute
        let alt = useAbs ? altitudeAMSL : altitudeAGL

        // Motor bars driven by config.motorWidget — read rcOutChannels.
        let motors = config.motorWidget.channels.map { entry -> TelemetrySample.MotorBar in
            let v = rcOutChannels[entry.channel]
            return TelemetrySample.MotorBar(
                label: entry.label,
                value: v ?? 1000,
                opacity: v == nil ? 0 : 1)
        }

        // Wind decomposition for the wind compass widget.
        let radDir = windDirection * .pi / 180
        let windVN = -windSpeed * cos(radDir)
        let windVE = -windSpeed * sin(radDir)

        // Headtracker suppression — instantaneous in live, with a fade
        // computed against the last state-change instant.
        let opacityScale = headtrackerOpacityScale(config: config)

        let distanceFromHome = home.flatMap { h in
            coordinate.map { h.distance(to: $0) }
        } ?? 0

        let gForce = TelemetrySample.GForce(
            lateralX: accelX / FlightLog.standardGravity,
            lateralY: accelY / FlightLog.standardGravity,
            vertical: -accelZ / FlightLog.standardGravity,
            peakLateral: peakLateralG)

        return TelemetrySample(
            time: t,
            groundSpeed: groundSpeed,
            airSpeed: airSpeed,
            altitude: alt,
            verticalSpeed: verticalSpeed,
            pitch: pitch,
            roll: roll,
            yaw: yaw,
            mode: mode,
            rangefinder: 0,
            rangefinderOpacity: 0,
            motors: motors,
            windVN: windVN,
            windVE: windVE,
            hasWind: hasWind,
            messages: messagesForOverlay(window: config.messageDisplaySeconds, now: t),
            coordinate: coordinate,
            hasGPS: !track.isEmpty,
            track: track,
            home: home,
            distanceFromHome: distanceFromHome,
            maxDistanceFromHome: maxDistanceFromHome,
            hasHome: home != nil,
            batteryVoltage: batteryVoltage,
            batteryCurrent: batteryCurrent,
            batteryConsumed: batteryConsumed,
            hasBattery: hasBattery,
            gForce: gForce,
            hasIMU: hasIMU,
            overlayOpacityScale: opacityScale)
    }

    private func messagesForOverlay(window: Double, now: Double)
        -> [TelemetrySample.Message] {
        messages.filter { now - $0.t <= window }.map {
            TelemetrySample.Message(text: $0.text, severity: $0.severity,
                                    age: now - $0.t)
        }
    }

    /// Live headtracker fade: track the most recent active/inactive flip
    /// against the wall-clock; the same fadeSeconds curve as the
    /// log-driven path produces a matching feel.
    private func headtrackerOpacityScale(config: OverlayConfig) -> Double {
        let cfg = config.headtracker
        guard cfg.isEnabled, let value = rcInChannels[cfg.channel] else {
            // Reset state when feature off, so re-enabling starts fresh.
            if headtrackerActive {
                headtrackerActive = false
                lastHeadtrackerFlipAt = Date()
            }
            return 1
        }
        let active = value < cfg.centerLow || value > cfg.centerHigh
        if active != headtrackerActive {
            headtrackerActive = active
            lastHeadtrackerFlipAt = Date()
        }
        let elapsed = Date().timeIntervalSince(lastHeadtrackerFlipAt)
        let progress = min(1, elapsed / max(0.05, cfg.fadeSeconds))
        return active ? 1 - progress : progress
    }

    // ── ArduPilot mode name (best-effort from HEARTBEAT custom_mode) ────
    /// ArduPlane custom_mode values — same table FlightLog uses.
    private static let planeModes: [UInt32: String] = [
        0: "MANUAL", 1: "CIRCLE", 2: "STABILIZE", 3: "TRAINING", 4: "ACRO",
        5: "FBWA", 6: "FBWB", 7: "CRUISE", 8: "AUTOTUNE", 10: "AUTO",
        11: "RTL", 12: "LOITER", 13: "TAKEOFF", 14: "AVOID_ADSB",
        15: "GUIDED", 16: "INITIALISING", 17: "QSTABILIZE", 18: "QHOVER",
        19: "QLOITER", 20: "QLAND", 21: "QRTL", 22: "QAUTOTUNE",
        23: "QACRO", 24: "THERMAL", 25: "LOITER_ALT_QLAND", 26: "AUTOLAND",
    ]

    private static func modeName(custom: UInt32, baseMode: UInt8) -> String {
        // MAV_MODE_FLAG_CUSTOM_MODE_ENABLED = 0x01 — only then is custom valid.
        if (baseMode & 0x01) == 0 { return "Manual" }
        return planeModes[custom] ?? "Mode \(custom)"
    }
}
