import Foundation
import CoreLocation

/// A geographic position decoded from the GPS log.
struct GeoPoint: Equatable {
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Great-circle ground distance to `other`, in metres.
    func distance(to other: GeoPoint) -> Double {
        let r = 6_371_000.0
        let dLat = (other.latitude - latitude) * .pi / 180
        let dLon = (other.longitude - longitude) * .pi / 180
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return r * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

/// One time-stamped point on the flight path.
struct TrackPoint {
    var t: Double
    var point: GeoPoint
}

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

    // ── GPS track ────────────────────────────────────────────────────────
    /// The flight path: every GPS fix with a valid position, in log order.
    private(set) var track: [TrackPoint] = []
    /// Home position — the origin logged by ArduPilot, or the fix at the
    /// first arming, or failing both the first valid fix.
    private(set) var home: GeoPoint?
    /// Ground distance from `home`, one entry per `track` point.
    private(set) var distanceFromHome: Series = []
    /// Greatest distance from home reached over the whole flight, in metres.
    private(set) var maxDistanceFromHome: Double = 0

    // ── Battery ──────────────────────────────────────────────────────────
    private(set) var batteryVoltage: Series = []     // V
    private(set) var batteryCurrent: Series = []     // A
    private(set) var batteryConsumed: Series = []    // mAh drawn

    // ── Accelerometer ────────────────────────────────────────────────────
    /// Body-frame specific force in m/s² from the primary IMU.
    private(set) var accelX: Series = []
    private(set) var accelY: Series = []
    private(set) var accelZ: Series = []
    /// Running peak of the lateral (X/Y) g magnitude — monotonic, so the
    /// value at time `t` is the greatest lateral load reached up to `t`.
    private(set) var peakLateralG: Series = []

    /// Standard gravity, for converting m/s² accelerometer readings to g.
    static let standardGravity: Double = 9.80665

    // ── Kalman-filtered channels ─────────────────────────────────────────
    /// Precomputed Kalman-smoothed versions of the noisiest channels, used
    /// when a widget opts into Kalman smoothing.
    private(set) var kalmanGpsSpeed: Series = []
    private(set) var kalmanAltitude: Series = []
    private(set) var kalmanAltitudeAbs: Series = []

    /// RCOU motor outputs in µs: the throttle (servo 5) and the four lift
    /// motors (servos 7–10). A `FadingSeries` so widgets can fade a channel
    /// out once it goes quiet.
    private(set) var motorThrottle = FadingSeries.empty
    private(set) var motorLift: [FadingSeries] = []
    /// Rangefinder readings, wrapped for the same drop-out fade.
    private(set) var rangefinderFade = FadingSeries.empty

    /// PWM at or above which an RCOU channel counts as "live".
    static let motorLiveThreshold: Double = 1000

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
            "RCOU", "BAT", "IMU", "ACC", "ARM", "ORGN",
        ]
        var t0: Double?

        // RCOU servo outputs collected raw, then wrapped after parsing.
        let liftServos = [7, 8, 9, 10]
        var throttleRaw: Series = []
        var liftRaw: [Series] = Array(repeating: [], count: liftServos.count)

        // Home detection inputs, resolved after the whole log is read.
        var originHome: GeoPoint?     // ORGN Type 0 — the logged home
        var firstArmTime: Double?     // first ARM with ArmState == 1
        var sawIMU = false            // prefer IMU; fall back to ACC

        try DataFlashParser.parse(data: data, wanted: wanted) { m in
            guard let tsec = Self.timestamp(of: m) else { return }
            if t0 == nil { t0 = tsec }
            let t = tsec - (t0 ?? tsec)

            switch m.name {
            case "GPS":
                if let s = m.fields["Spd"]?.double { gpsSpeed.append((t, s)) }
                if let a = m.fields["Alt"]?.double { altitudeAbs.append((t, a)) }
                // Lat/Lng arrive as integer degrees × 1e7. Drop the (0, 0)
                // null island that a fix-less GPS message reports.
                if let lat = m.fields["Lat"]?.double,
                   let lng = m.fields["Lng"]?.double,
                   abs(lat) > 1 || abs(lng) > 1 {
                    track.append(TrackPoint(
                        t: t, point: GeoPoint(latitude: lat / 1e7,
                                              longitude: lng / 1e7)))
                }
            case "BAT":
                if let v = m.fields["Volt"]?.double { batteryVoltage.append((t, v)) }
                if let c = m.fields["Curr"]?.double { batteryCurrent.append((t, c)) }
                if let used = m.fields["CurrTot"]?.double {
                    batteryConsumed.append((t, used))
                }
            case "IMU":
                // ArduPilot logs each inertial sensor as a separate instance;
                // the primary one (I == 0) is the EKF's chosen sensor.
                if Int(m.fields["I"]?.double ?? 0) == 0 {
                    sawIMU = true
                    if let x = m.fields["AccX"]?.double { accelX.append((t, x)) }
                    if let y = m.fields["AccY"]?.double { accelY.append((t, y)) }
                    if let z = m.fields["AccZ"]?.double { accelZ.append((t, z)) }
                }
            case "ACC":
                // Older logs carry raw accel in ACC; only used if no IMU.
                if !sawIMU {
                    if let x = m.fields["AccX"]?.double { accelX.append((t, x)) }
                    if let y = m.fields["AccY"]?.double { accelY.append((t, y)) }
                    if let z = m.fields["AccZ"]?.double { accelZ.append((t, z)) }
                }
            case "ARM":
                let armed = (m.fields["ArmState"]?.double ?? 0) != 0
                if armed, firstArmTime == nil { firstArmTime = t }
            case "ORGN":
                // Type 0 is the home origin; Type 1 is the EKF origin.
                if Int(m.fields["Type"]?.double ?? -1) == 0,
                   let lat = m.fields["Lat"]?.double,
                   let lng = m.fields["Lng"]?.double,
                   abs(lat) > 1 || abs(lng) > 1 {
                    originHome = GeoPoint(latitude: lat / 1e7,
                                          longitude: lng / 1e7)
                }
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
            case "RCOU":
                if let v = m.fields["C5"]?.double { throttleRaw.append((t, v)) }
                for (i, ch) in liftServos.enumerated() {
                    if let v = m.fields["C\(ch)"]?.double {
                        liftRaw[i].append((t, v))
                    }
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

        motorThrottle = FadingSeries(throttleRaw, threshold: Self.motorLiveThreshold)
        motorLift = liftRaw.map { FadingSeries($0, threshold: Self.motorLiveThreshold) }
        // Every rangefinder sample is already a valid reading, so any of them
        // counts as "live" — a zero threshold makes the fade purely recency.
        rangefinderFade = FadingSeries(rangefinder, threshold: 0)

        resolveHome(originHome: originHome, firstArmTime: firstArmTime)
        buildPeakG()

        kalmanGpsSpeed = Self.kalman(gpsSpeed, q: 0.2, r: 4)
        kalmanAltitude = Self.kalman(altitude, q: 0.1, r: 2)
        kalmanAltitudeAbs = Self.kalman(altitudeAbs, q: 0.1, r: 2)
    }

    /// A 1-D constant-position Kalman filter over a time series. `q` is the
    /// process noise per second, `r` the measurement noise.
    private static func kalman(_ s: Series, q: Double, r: Double) -> Series {
        guard let first = s.first else { return [] }
        var x = first.v
        var p = 1.0
        var prevT = first.t
        var out: Series = []
        out.reserveCapacity(s.count)
        for sample in s {
            let dt = max(0, sample.t - prevT)
            prevT = sample.t
            p += q * (dt + 0.001)
            let k = p / (p + r)
            x += k * (sample.v - x)
            p *= (1 - k)
            out.append((sample.t, x))
        }
        return out
    }

    /// Build the monotonic running-peak series for the lateral g load.
    private func buildPeakG() {
        let g = Self.standardGravity
        var peak = 0.0
        var out: Series = []
        out.reserveCapacity(accelX.count)
        for i in accelX.indices {
            let x = accelX[i].v
            let y = i < accelY.count ? accelY[i].v : 0
            peak = max(peak, (x * x + y * y).squareRoot() / g)
            out.append((accelX[i].t, peak))
        }
        peakLateralG = out
    }

    /// Pick the home position and build the distance-from-home series.
    /// Preference: the logged origin, then the fix at first arming, then the
    /// first valid fix in the track.
    private func resolveHome(originHome: GeoPoint?, firstArmTime: Double?) {
        if let originHome {
            home = originHome
        } else if let armTime = firstArmTime,
                  let near = trackPoint(nearest: armTime) {
            home = near.point
        } else {
            home = track.first?.point
        }

        guard let home else { return }
        distanceFromHome = track.map { ($0.t, home.distance(to: $0.point)) }
        maxDistanceFromHome = distanceFromHome.map(\.v).max() ?? 0
    }

    /// The track point whose timestamp is closest to `t`.
    private func trackPoint(nearest t: Double) -> TrackPoint? {
        track.min { abs($0.t - t) < abs($1.t - t) }
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

    /// The flight position at telemetry time `t`, interpolated along the
    /// track. `nil` when the log carries no GPS fixes.
    func coordinate(at t: Double) -> GeoPoint? {
        guard let first = track.first else { return nil }
        if t <= first.t { return first.point }
        guard let last = track.last else { return nil }
        if t >= last.t { return last.point }

        var lo = 0
        var hi = track.count - 1
        while lo < hi - 1 {
            let mid = (lo + hi) / 2
            if track[mid].t <= t { lo = mid } else { hi = mid }
        }
        let a = track[lo]
        let b = track[hi]
        guard b.t != a.t else { return a.point }
        let f = (t - a.t) / (b.t - a.t)
        return GeoPoint(
            latitude: a.point.latitude + f * (b.point.latitude - a.point.latitude),
            longitude: a.point.longitude + f * (b.point.longitude - a.point.longitude))
    }

    /// Moving average of `series` over a `window`-second span centred on `t`.
    /// Falls back to interpolation when the window catches no samples.
    func sampleSmoothed(_ series: Series, at t: Double,
                        window: Double) -> Double {
        guard window > 0, !series.isEmpty else { return sample(series, at: t) }
        let half = window / 2
        var lo = 0, hi = series.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if series[mid].t < t - half { lo = mid + 1 } else { hi = mid }
        }
        var sum = 0.0, count = 0
        var i = lo
        while i < series.count, series[i].t <= t + half {
            sum += series[i].v
            count += 1
            i += 1
        }
        return count > 0 ? sum / Double(count) : sample(series, at: t)
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

/// A telemetry series that also answers, in O(log n), "how long since the
/// value was last at or above a threshold". Widgets use this to fade out
/// when a channel goes quiet — a motor stopping, a sensor dropping out.
struct FadingSeries {
    let samples: FlightLog.Series
    /// Parallel to `samples`: time of the most recent in-range sample at or
    /// before that index (`-infinity` until the first one occurs).
    private let lastLive: [Double]

    static let empty = FadingSeries([], threshold: 0)

    init(_ samples: FlightLog.Series, threshold: Double) {
        self.samples = samples
        var acc: [Double] = []
        acc.reserveCapacity(samples.count)
        var last = -Double.infinity
        for s in samples {
            if s.v >= threshold { last = s.t }
            acc.append(last)
        }
        lastLive = acc
    }

    /// Seconds since the value was last at or above the threshold, as of `t`.
    /// `.infinity` when it never has been (or there is no data).
    func secondsSinceLive(at t: Double) -> Double {
        guard let first = samples.first, t >= first.t else { return .infinity }
        var lo = 0
        var hi = samples.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if samples[mid].t <= t { lo = mid } else { hi = mid - 1 }
        }
        let last = lastLive[lo]
        return last.isFinite ? t - last : .infinity
    }
}
