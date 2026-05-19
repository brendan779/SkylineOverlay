import Foundation

/// Telemetry interpolated to a single instant — what the widgets draw.
///
/// Built once per frame so each widget reads plain values instead of
/// touching `FlightLog` directly.
struct TelemetrySample {
    var time: Double            // telemetry time (s)
    var groundSpeed: Double     // m/s
    var airSpeed: Double        // m/s
    var altitude: Double        // m, per the configured datum
    var verticalSpeed: Double   // m/s
    var pitch: Double           // deg
    var roll: Double            // deg
    var yaw: Double             // deg, 0..<360
    var mode: String
    var rangefinder: Double         // m AGL; meaningful while rangefinderOpacity > 0
    var rangefinderOpacity: Double  // fades to 0 when readings stop
    var throttle: MotorBar          // RCOU servo 5
    var liftMotors: [MotorBar]      // RCOU servos 7…10
    var windVN: Double          // m/s, wind velocity north
    var windVE: Double          // m/s, wind velocity east
    var hasWind: Bool
    var messages: [Message]

    // ── GPS / position ───────────────────────────────────────────────────
    var coordinate: GeoPoint?       // current flight position
    var hasGPS: Bool
    var track: [TrackPoint]         // the whole flight path
    var home: GeoPoint?             // home position, if known
    var distanceFromHome: Double    // m, 2D ground distance
    var maxDistanceFromHome: Double // m, greatest reached over the flight
    var hasHome: Bool

    // ── Battery ──────────────────────────────────────────────────────────
    var batteryVoltage: Double      // V
    var batteryCurrent: Double      // A
    var batteryConsumed: Double     // mAh drawn
    var hasBattery: Bool

    // ── G-force ──────────────────────────────────────────────────────────
    var gForce: GForce
    var hasIMU: Bool

    struct Message {
        var text: String
        var severity: Int
        var age: Double         // seconds since the message appeared
    }

    /// Accelerometer load in g. Lateral X/Y drive the 2-axis ball; vertical
    /// is the classic 1-g-at-rest load. `peakLateral` is the running maximum
    /// of the lateral magnitude up to the current playhead.
    struct GForce {
        var lateralX: Double
        var lateralY: Double
        var vertical: Double
        var peakLateral: Double

        var lateralMagnitude: Double {
            (lateralX * lateralX + lateralY * lateralY).squareRoot()
        }
    }

    /// One RCOU channel: its PWM output and a fade level that drops to 0 a
    /// second after the channel falls below the live threshold.
    struct MotorBar {
        var value: Double       // servo PWM, µs (≈1000…2000)
        var opacity: Double     // 0…1
    }

    /// Sample `log` at telemetry time `t`.
    static func make(from log: FlightLog, at t: Double,
                     config: OverlayConfig) -> TelemetrySample {
        let absolute = config.altitudeDatum == .absolute
        let altSeries = absolute ? log.altitudeAbs : log.altitude

        // Per-widget smoothing: Kalman uses the precomputed channel, the
        // moving average filters at sample time over the configured window.
        func smoothed(_ kind: WidgetKind, _ series: FlightLog.Series,
                      kalman: FlightLog.Series? = nil) -> Double {
            let s = config.smoothing(for: kind)
            if s.useKalman, let kalman { return log.sample(kalman, at: t) }
            return log.sampleSmoothed(series, at: t, window: s.window)
        }

        var verticalSpeed = 0.0
        if log.altitude.count >= 2 {
            let dt = 0.5
            let a1 = log.sample(log.altitude, at: t)
            let a0 = log.sample(log.altitude, at: max(0, t - dt))
            verticalSpeed = (a1 - a0) / dt
        }

        var yaw = log.sample(log.yaw, at: t)
            .truncatingRemainder(dividingBy: 360)
        if yaw < 0 { yaw += 360 }

        let rangefinder = log.sample(log.rangefinder, at: t)
        let rangefinderOpacity = fade(
            log.rangefinderFade.secondsSinceLive(at: t), hold: 2.0, ramp: 0.5)

        let throttle = motorBar(log.motorThrottle, log: log, at: t)
        let liftMotors = log.motorLift.map { motorBar($0, log: log, at: t) }

        let windVN = log.windVN.isEmpty ? 0 : log.sample(log.windVN, at: t)
        let windVE = log.windVE.isEmpty ? 0 : log.sample(log.windVE, at: t)
        let windSpeed = (windVN * windVN + windVE * windVE).squareRoot()

        let messages = log.messagesAt(t, window: config.messageDisplaySeconds)
            .map { Message(text: $0.text, severity: $0.severity, age: t - $0.t) }

        let g = FlightLog.standardGravity
        let gForce = GForce(
            lateralX: log.sample(log.accelX, at: t) / g,
            lateralY: log.sample(log.accelY, at: t) / g,
            // AccZ reads ≈ −g at rest; negate so level flight is +1 g.
            vertical: -log.sample(log.accelZ, at: t) / g,
            peakLateral: log.sample(log.peakLateralG, at: t))

        return TelemetrySample(
            time: t,
            groundSpeed: smoothed(.groundSpeed, log.gpsSpeed,
                                  kalman: log.kalmanGpsSpeed),
            airSpeed: smoothed(.airSpeed, log.airSpeed),
            altitude: smoothed(.altitude, altSeries,
                               kalman: absolute ? log.kalmanAltitudeAbs
                                                : log.kalmanAltitude),
            verticalSpeed: verticalSpeed,
            pitch: log.sample(log.pitch, at: t),
            roll: log.sample(log.roll, at: t),
            yaw: yaw,
            mode: log.modeAt(t),
            rangefinder: rangefinder,
            rangefinderOpacity: rangefinderOpacity,
            throttle: throttle,
            liftMotors: liftMotors,
            windVN: windVN,
            windVE: windVE,
            hasWind: !log.windVN.isEmpty && windSpeed >= 0.5,
            messages: messages,
            coordinate: log.coordinate(at: t),
            hasGPS: !log.track.isEmpty,
            track: log.track,
            home: log.home,
            distanceFromHome: log.sample(log.distanceFromHome, at: t),
            maxDistanceFromHome: log.maxDistanceFromHome,
            hasHome: log.home != nil,
            batteryVoltage: log.sample(log.batteryVoltage, at: t),
            batteryCurrent: log.sample(log.batteryCurrent, at: t),
            batteryConsumed: log.sample(log.batteryConsumed, at: t),
            hasBattery: !log.batteryVoltage.isEmpty,
            gForce: gForce,
            hasIMU: !log.accelZ.isEmpty)
    }

    /// Sample one RCOU channel and pair it with its drop-out fade level.
    private static func motorBar(_ channel: FadingSeries, log: FlightLog,
                                 at t: Double) -> MotorBar {
        MotorBar(value: log.sample(channel.samples, at: t),
                 opacity: fade(channel.secondsSinceLive(at: t),
                               hold: 1.0, ramp: 0.4))
    }

    /// Full opacity while a channel is live; once it has been quiet for
    /// longer than `hold` seconds, ramp to 0 over the next `ramp` seconds.
    private static func fade(_ secondsSinceLive: Double,
                             hold: Double, ramp: Double) -> Double {
        if secondsSinceLive <= hold { return 1 }
        return max(0, 1 - (secondsSinceLive - hold) / ramp)
    }

    /// A neutral sample for previews and the empty state.
    static let placeholder = TelemetrySample(
        time: 0, groundSpeed: 0, airSpeed: 0, altitude: 0, verticalSpeed: 0,
        pitch: 0, roll: 0, yaw: 0, mode: "—",
        rangefinder: 0, rangefinderOpacity: 0,
        throttle: MotorBar(value: 1000, opacity: 1),
        liftMotors: Array(repeating: MotorBar(value: 1000, opacity: 1), count: 4),
        windVN: 0, windVE: 0, hasWind: false, messages: [],
        coordinate: nil, hasGPS: false, track: [], home: nil,
        distanceFromHome: 0, maxDistanceFromHome: 0, hasHome: false,
        batteryVoltage: 0, batteryCurrent: 0, batteryConsumed: 0,
        hasBattery: false,
        gForce: GForce(lateralX: 0, lateralY: 0, vertical: 1, peakLateral: 0),
        hasIMU: false)
}
