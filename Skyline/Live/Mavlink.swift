import Foundation

/// MAVLink v1 + v2 framing parser and decoders for the message subset
/// Skyline needs to drive the HUD in live mode.
///
/// Hand-rolled rather than pulling in a full MAVLink dependency — we only
/// touch ~12 messages and need predictable, auditable behaviour. CRC uses
/// the standard MAVLink CRC-16 (ITU/CCITT variant, init 0xFFFF) with a
/// trailing CRC_EXTRA byte per message ID.
enum Mavlink {

    // ── Framing constants ───────────────────────────────────────────────
    static let v1Start: UInt8 = 0xFE
    static let v2Start: UInt8 = 0xFD

    static let v1HeaderLen = 6        // start + len + seq + sysid + compid + msgid
    static let v2HeaderLen = 10       // start + len + incompat + compat + seq + sys + comp + msgid(3)

    /// Maximum raw payload bytes. MAVLink v2 trims trailing zero bytes, so
    /// the on-wire len can be smaller than the message's defined size; the
    /// decoders pad with zeros to match.
    static let maxPayload = 255

    // ── Message IDs we decode ───────────────────────────────────────────
    enum MsgID: UInt32 {
        case heartbeat = 0
        case sysStatus = 1
        case gpsRawInt = 24
        case scaledImu = 26
        case attitude = 30
        case globalPositionInt = 33
        case servoOutputRaw = 36
        case rcChannels = 65
        case vfrHud = 74
        case highresImu = 105
        case batteryStatus = 147
        case wind = 168                 // ardupilotmega
        case homePosition = 242
        case statustext = 253
    }

    /// CRC_EXTRA values for every supported message ID. Tied to the
    /// canonical MAVLink XML definitions; do not change without verifying
    /// against `mavgen`-generated headers.
    static let crcExtra: [UInt32: UInt8] = [
        0:   50,   // HEARTBEAT
        1:   124,  // SYS_STATUS
        24:  24,   // GPS_RAW_INT
        26:  170,  // SCALED_IMU
        30:  39,   // ATTITUDE
        33:  104,  // GLOBAL_POSITION_INT
        36:  222,  // SERVO_OUTPUT_RAW
        65:  118,  // RC_CHANNELS
        74:  20,   // VFR_HUD
        105: 93,   // HIGHRES_IMU
        147: 154,  // BATTERY_STATUS
        168: 1,    // WIND (ardupilotmega)
        242: 104,  // HOME_POSITION
        253: 83,   // STATUSTEXT
    ]

    // ── CRC-16 (MAVLink) ────────────────────────────────────────────────
    /// Standard MAVLink CRC update — equivalent to CRC-16/MCRF4XX.
    @inline(__always)
    static func crcUpdate(_ acc: inout UInt16, _ byte: UInt8) {
        var tmp = byte ^ UInt8(truncatingIfNeeded: acc & 0xFF)
        tmp ^= (tmp << 4) & 0xFF
        let t16 = UInt16(tmp)
        acc = (acc >> 8) ^ (t16 << 8) ^ (t16 << 3) ^ (t16 >> 4)
    }

    static func crc(over bytes: ArraySlice<UInt8>, crcExtra: UInt8) -> UInt16 {
        var acc: UInt16 = 0xFFFF
        for b in bytes { crcUpdate(&acc, b) }
        crcUpdate(&acc, crcExtra)
        return acc
    }

    // ── Decoded frame ───────────────────────────────────────────────────
    struct Frame {
        let msgId: UInt32
        let sysId: UInt8
        let compId: UInt8
        let seq: UInt8
        /// Payload padded with zeros up to the message's full size, so the
        /// decoders can read fields without bounds checks.
        let payload: [UInt8]
    }

    // ── Streaming parser ────────────────────────────────────────────────
    /// Consumes bytes from a rolling buffer and yields complete, CRC-valid
    /// frames. Discards mis-syncs by sliding the start one byte forward.
    static func parse(_ buf: inout [UInt8]) -> [Frame] {
        var out: [Frame] = []
        var i = 0
        while i < buf.count {
            let b = buf[i]
            if b == v1Start {
                if let frame = tryV1(buf, at: i) {
                    out.append(frame.frame)
                    i += frame.length
                    continue
                }
                // Not enough bytes yet, OR bad CRC — fall through.
                if buf.count - i < v1HeaderLen + 2 { break }
                i += 1
            } else if b == v2Start {
                if let frame = tryV2(buf, at: i) {
                    out.append(frame.frame)
                    i += frame.length
                    continue
                }
                if buf.count - i < v2HeaderLen + 2 { break }
                i += 1
            } else {
                i += 1
            }
        }
        if i > 0 { buf.removeFirst(i) }
        return out
    }

    private static func tryV1(_ buf: [UInt8], at start: Int)
        -> (frame: Frame, length: Int)? {
        guard buf.count >= start + v1HeaderLen else { return nil }
        let len = Int(buf[start + 1])
        let total = v1HeaderLen + len + 2
        guard buf.count >= start + total else { return nil }
        let msgId = UInt32(buf[start + 5])
        guard let crcX = crcExtra[msgId] else { return (frame: dummy(), length: total) }
        let crcRange = (start + 1)...(start + v1HeaderLen + len - 1)
        let computed = crc(over: buf[crcRange], crcExtra: crcX)
        let wireLo = buf[start + v1HeaderLen + len]
        let wireHi = buf[start + v1HeaderLen + len + 1]
        let wire = UInt16(wireLo) | (UInt16(wireHi) << 8)
        guard wire == computed else { return nil }

        var payload = [UInt8](repeating: 0, count: maxPayload)
        if len > 0 {
            for k in 0..<len {
                payload[k] = buf[start + v1HeaderLen + k]
            }
        }
        let frame = Frame(msgId: msgId,
                          sysId: buf[start + 3],
                          compId: buf[start + 4],
                          seq: buf[start + 2],
                          payload: payload)
        return (frame, total)
    }

    private static func tryV2(_ buf: [UInt8], at start: Int)
        -> (frame: Frame, length: Int)? {
        guard buf.count >= start + v2HeaderLen else { return nil }
        let len = Int(buf[start + 1])
        let incompat = buf[start + 2]
        let signed = (incompat & 0x01) != 0
        let signatureLen = signed ? 13 : 0
        let total = v2HeaderLen + len + 2 + signatureLen
        guard buf.count >= start + total else { return nil }
        let msgId = UInt32(buf[start + 7])
            | (UInt32(buf[start + 8]) << 8)
            | (UInt32(buf[start + 9]) << 16)
        guard let crcX = crcExtra[msgId] else { return (frame: dummy(), length: total) }
        let crcRange = (start + 1)...(start + v2HeaderLen + len - 1)
        let computed = crc(over: buf[crcRange], crcExtra: crcX)
        let wireLo = buf[start + v2HeaderLen + len]
        let wireHi = buf[start + v2HeaderLen + len + 1]
        let wire = UInt16(wireLo) | (UInt16(wireHi) << 8)
        guard wire == computed else { return nil }

        var payload = [UInt8](repeating: 0, count: maxPayload)
        if len > 0 {
            for k in 0..<len {
                payload[k] = buf[start + v2HeaderLen + k]
            }
        }
        let frame = Frame(msgId: msgId,
                          sysId: buf[start + 5],
                          compId: buf[start + 6],
                          seq: buf[start + 4],
                          payload: payload)
        return (frame, total)
    }

    private static func dummy() -> Frame {
        Frame(msgId: 0, sysId: 0, compId: 0, seq: 0,
              payload: [UInt8](repeating: 0, count: maxPayload))
    }

    // ── Little-endian field readers ─────────────────────────────────────
    @inline(__always)
    static func u16(_ p: [UInt8], _ off: Int) -> UInt16 {
        UInt16(p[off]) | (UInt16(p[off + 1]) << 8)
    }

    @inline(__always)
    static func u32(_ p: [UInt8], _ off: Int) -> UInt32 {
        UInt32(p[off])
            | (UInt32(p[off + 1]) << 8)
            | (UInt32(p[off + 2]) << 16)
            | (UInt32(p[off + 3]) << 24)
    }

    @inline(__always)
    static func u64(_ p: [UInt8], _ off: Int) -> UInt64 {
        var v: UInt64 = 0
        for k in 0..<8 { v |= UInt64(p[off + k]) << (8 * k) }
        return v
    }

    @inline(__always)
    static func i16(_ p: [UInt8], _ off: Int) -> Int16 {
        Int16(bitPattern: u16(p, off))
    }

    @inline(__always)
    static func i32(_ p: [UInt8], _ off: Int) -> Int32 {
        Int32(bitPattern: u32(p, off))
    }

    @inline(__always)
    static func f32(_ p: [UInt8], _ off: Int) -> Float {
        Float(bitPattern: u32(p, off))
    }

    static func cString(_ p: [UInt8], _ off: Int, _ len: Int) -> String {
        var bytes: [UInt8] = []
        for k in 0..<len {
            let b = p[off + k]
            if b == 0 { break }
            bytes.append(b)
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}

// ── Decoded message structs ─────────────────────────────────────────────
//
// Wire field order is by descending field size within the "base" payload
// (MAVLink reorders fields from XML order so largest-types-first). Each
// decoder picks fields from a padded payload buffer.

extension Mavlink {

    struct Heartbeat {
        let customMode: UInt32, type: UInt8, autopilot: UInt8
        let baseMode: UInt8, systemStatus: UInt8, mavlinkVersion: UInt8

        init(_ p: [UInt8]) {
            customMode = u32(p, 0)
            type = p[4]; autopilot = p[5]; baseMode = p[6]
            systemStatus = p[7]; mavlinkVersion = p[8]
        }
    }

    struct SysStatus {
        let voltageBattery: UInt16    // mV
        let currentBattery: Int16     // 10*mA, -1 if not available
        let batteryRemaining: Int8    // %

        init(_ p: [UInt8]) {
            voltageBattery = u16(p, 14)
            currentBattery = i16(p, 16)
            batteryRemaining = Int8(bitPattern: p[30])
        }
    }

    struct GpsRawInt {
        let lat: Int32, lon: Int32, alt: Int32   // 1e7 deg, mm
        let fixType: UInt8, satellitesVisible: UInt8

        init(_ p: [UInt8]) {
            lat = i32(p, 8); lon = i32(p, 12); alt = i32(p, 16)
            fixType = p[28]
            satellitesVisible = p[29]
        }
    }

    struct ScaledImu {
        let xacc: Int16, yacc: Int16, zacc: Int16   // mG
        init(_ p: [UInt8]) {
            xacc = i16(p, 4); yacc = i16(p, 6); zacc = i16(p, 8)
        }
    }

    struct Attitude {
        let roll: Float, pitch: Float, yaw: Float    // rad
        init(_ p: [UInt8]) {
            roll = f32(p, 4); pitch = f32(p, 8); yaw = f32(p, 12)
        }
    }

    struct GlobalPositionInt {
        let lat: Int32, lon: Int32             // 1e7 deg
        let alt: Int32, relativeAlt: Int32     // mm AMSL, mm AGL
        let vx: Int16, vy: Int16, vz: Int16    // cm/s
        let hdg: UInt16                        // cdeg
        init(_ p: [UInt8]) {
            lat = i32(p, 4); lon = i32(p, 8)
            alt = i32(p, 12); relativeAlt = i32(p, 16)
            vx = i16(p, 20); vy = i16(p, 22); vz = i16(p, 24)
            hdg = u16(p, 26)
        }
    }

    struct ServoOutputRaw {
        let timeUsec: UInt32
        /// Channels 1..16 (uint16 µs). v1 carries only 1..8; v2 extensions
        /// add 9..16, padded to 0 when not present.
        let servos: [UInt16]
        init(_ p: [UInt8]) {
            timeUsec = u32(p, 0)
            var s = [UInt16](repeating: 0, count: 16)
            for k in 0..<8 { s[k] = u16(p, 4 + 2 * k) }
            // v2 extensions follow the `port` byte at offset 20.
            for k in 0..<8 { s[8 + k] = u16(p, 21 + 2 * k) }
            servos = s
        }
    }

    struct RcChannels {
        /// Channels 1..18 (uint16 µs).
        let channels: [UInt16]
        let count: UInt8
        let rssi: UInt8
        init(_ p: [UInt8]) {
            var c = [UInt16](repeating: 0, count: 18)
            for k in 0..<18 { c[k] = u16(p, 4 + 2 * k) }
            channels = c
            count = p[40]; rssi = p[41]
        }
    }

    struct VfrHud {
        let airspeed: Float, groundspeed: Float, alt: Float, climb: Float
        let heading: Int16, throttle: UInt16
        init(_ p: [UInt8]) {
            airspeed = f32(p, 0); groundspeed = f32(p, 4)
            alt = f32(p, 8); climb = f32(p, 12)
            heading = i16(p, 16); throttle = u16(p, 18)
        }
    }

    struct HighresImu {
        let xacc: Float, yacc: Float, zacc: Float   // m/s²
        init(_ p: [UInt8]) {
            xacc = f32(p, 8); yacc = f32(p, 12); zacc = f32(p, 16)
        }
    }

    struct BatteryStatus {
        let currentConsumed: Int32   // mAh
        let currentBattery: Int16    // 10*mA
        let voltagesMv: [UInt16]     // up to 10 cells, mV
        let batteryRemaining: Int8   // %

        init(_ p: [UInt8]) {
            currentConsumed = i32(p, 0)
            var v: [UInt16] = []
            for k in 0..<10 { v.append(u16(p, 10 + 2 * k)) }
            voltagesMv = v
            currentBattery = i16(p, 30)
            batteryRemaining = Int8(bitPattern: p[35])
        }

        /// Pack voltage in volts (sum of valid cells; 0xFFFF means "not used").
        var packVoltage: Double {
            voltagesMv.reduce(0) { $0 + ($1 == 0xFFFF ? 0 : Double($1)) } / 1000
        }
    }

    struct Wind {
        let direction: Float    // deg
        let speed: Float        // m/s
        init(_ p: [UInt8]) {
            direction = f32(p, 0); speed = f32(p, 4)
        }
    }

    struct HomePosition {
        let latitude: Int32, longitude: Int32, altitude: Int32  // 1e7 deg, mm
        init(_ p: [UInt8]) {
            latitude = i32(p, 0)
            longitude = i32(p, 4)
            altitude = i32(p, 8)
        }
    }

    struct StatusText {
        let severity: UInt8
        let text: String
        init(_ p: [UInt8]) {
            severity = p[0]
            text = cString(p, 1, 50)
        }
    }
}
