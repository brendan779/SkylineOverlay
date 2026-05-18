import Foundation

/// Time-indexed telemetry parsed from an ArduPilot DataFlash log.
///
/// Swift port of the Python renderer's `LogData`. Every series is a list of
/// `(time, value)` pairs in log order; `sample(_:at:)` interpolates linearly.
/// Times are seconds relative to the first telemetry message.
final class FlightLog {

    typealias Series = [(t: Double, v: Double)]

    private(set) var gpsSpeed: Series = []
    private(set) var airSpeed: Series = []
    private(set) var altitude: Series = []        // relative, zeroed at start
    private(set) var altitudeAbs: Series = []     // AMSL
    private(set) var pitch: Series = []
    private(set) var roll: Series = []
    private(set) var yaw: Series = []
    private(set) var windVN: Series = []
    private(set) var windVE: Series = []
    private(set) var rangefinder: Series = []
    private(set) var flightMode: [(t: Double, mode: String)] = []
    private(set) var messages: [(t: Double, text: String, severity: Int)] = []

    enum LogError: Error { case empty }

    convenience init(url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    init(data: Data) throws {
        try build(from: data)
        if duration() == 0 { throw LogError.empty }
    }

    // ── Parse ────────────────────────────────────────────────────────────
    private func build(from data: Data) throws {
        let wanted: Set<String> = [
            "GPS", "ARSP", "BARO", "ATT", "MODE", "MSG", "RFND", "XKF2", "NKF2",
        ]
        var t0: Double?

        try DataFlashParser.parse(data: data, wanted: wanted) { m in
            guard let tsec = Self.timestamp(of: m) else { return }
            if t0 == nil { t0 = tsec }
            let t = tsec - (t0 ?? tsec)

            switch m.name {
            case "GPS":
                if let s = m.fields["Spd"]?.double { gpsSpeed.append((t, s)) }
                if let a = m.fields["Alt"]?.double { altitudeAbs.append((t, a)) }
            case "ARSP":
                if let a = m.fields["Airspeed"]?.double { airSpeed.append((t, a)) }
            case "BARO":
                if let a = m.fields["Alt"]?.double { altitude.append((t, a)) }
            case "ATT":
                if let p = m.fields["Pitch"]?.double { pitch.append((t, p)) }
                if let r = m.fields["Roll"]?.double  { roll.append((t, r)) }
                if let y = m.fields["Yaw"]?.double   { yaw.append((t, y)) }
            case "MODE":
                let num = Int(m.fields["Mode"]?.double ?? 0)
                flightMode.append((t, Self.modeName(num)))
            case "MSG":
                let text = m.fields["Message"]?.string ?? ""
                messages.append((t, text, 6))
            case "RFND":
                let status = Int((m.fields["Status"] ?? m.fields["Stat"])?.double ?? 0)
                if status == 4, let d = m.fields["Dist"]?.double, d > 0 {
                    rangefinder.append((t, d))
                }
            case "XKF2", "NKF2":
                if let vn = m.fields["VWN"]?.double,
                   let ve = m.fields["VWE"]?.double,
                   abs(vn) > 1e-4 || abs(ve) > 1e-4 {
                    windVN.append((t, vn))
                    windVE.append((t, ve))
                }
            default:
                break
            }
        }

        // Relative altitude — zero at the first BARO sample.
        if let a0 = altitude.first?.v {
            altitude = altitude.map { ($0.t, $0.v - a0) }
        }
    }

    private static func timestamp(of m: LogMessage) -> Double? {
        if let us = m.fields["TimeUS"]?.double { return us / 1_000_000 }
        if let ms = m.fields["TimeMS"]?.double { return ms / 1_000 }
        return nil
    }

    // ── Queries ──────────────────────────────────────────────────────────
    /// Linear interpolation of a series at time `t`.
    func sample(_ series: Series, at t: Double, default def: Double = 0) -> Double {
        guard let first = series.first else { return def }
        if t <= first.t { return first.v }
        guard let last = series.last else { return def }
        if t >= last.t { return last.v }

        var lo = 0
        var hi = series.count - 1
        while lo < hi - 1 {
            let mid = (lo + hi) / 2
            if series[mid].t <= t { lo = mid } else { hi = mid }
        }
        let a = series[lo]
        let b = series[hi]
        if b.t == a.t { return a.v }
        return a.v + (t - a.t) / (b.t - a.t) * (b.v - a.v)
    }

    func modeAt(_ t: Double) -> String {
        guard var mode = flightMode.first?.mode else { return "Unknown" }
        for entry in flightMode {
            if entry.t <= t { mode = entry.mode } else { break }
        }
        return mode
    }

    func messagesAt(_ t: Double, window: Double)
        -> [(t: Double, text: String, severity: Int)] {
        messages.filter { t - window <= $0.t && $0.t <= t }
    }

    func duration() -> Double {
        [altitude.last?.t, gpsSpeed.last?.t, pitch.last?.t, flightMode.last?.t]
            .compactMap { $0 }
            .max() ?? 0
    }

    // ── ArduPlane flight modes (fixed-wing + VTOL/quadplane) ─────────────
    private static let planeModes: [Int: String] = [
        0: "MANUAL", 1: "CIRCLE", 2: "STABILIZE", 3: "TRAINING", 4: "ACRO",
        5: "FBWA", 6: "FBWB", 7: "CRUISE", 8: "AUTOTUNE", 10: "AUTO",
        11: "RTL", 12: "LOITER", 13: "TAKEOFF", 14: "AVOID_ADSB", 15: "GUIDED",
        16: "INITIALISING", 17: "QSTABILIZE", 18: "QHOVER", 19: "QLOITER",
        20: "QLAND", 21: "QRTL", 22: "QAUTOTUNE", 23: "QACRO", 24: "THERMAL",
        25: "LOITER_ALT_QLAND", 26: "AUTOLAND",
    ]

    static func modeName(_ n: Int) -> String {
        planeModes[n] ?? "Mode \(n)"
    }
}
