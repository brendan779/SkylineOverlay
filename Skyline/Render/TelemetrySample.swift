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

    struct Message {
        var text: String
        var severity: Int
        var age: Double         // seconds since the message appeared
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
        let altSeries = config.altitudeDatum == .absolute
            ? log.altitudeAbs : log.altitude

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

        return TelemetrySample(
            time: t,
            groundSpeed: log.sample(log.gpsSpeed, at: t),
            airSpeed: log.sample(log.airSpeed, at: t),
            altitude: log.sample(altSeries, at: t),
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
            messages: messages)
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
        windVN: 0, windVE: 0, hasWind: false, messages: [])
}
