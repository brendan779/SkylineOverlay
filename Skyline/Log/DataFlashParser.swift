import Foundation

/// A value decoded from one log field.
enum LogValue {
    case int(Int64)
    case uint(UInt64)
    case double(Double)
    case string(String)

    var double: Double? {
        switch self {
        case .int(let v):    return Double(v)
        case .uint(let v):   return Double(v)
        case .double(let v): return v
        case .string:        return nil
        }
    }

    var string: String? {
        if case .string(let s) = self { return s }
        return nil
    }
}

/// Schema for one message type, taken from an FMT record.
struct LogFormat {
    let type: UInt8
    let length: Int          // total message bytes, incl. the 3-byte header
    let name: String
    let format: String
    let columns: [String]
}

/// One decoded log message.
struct LogMessage {
    let name: String
    let fields: [String: LogValue]
}

/// Streaming parser for the ArduPilot DataFlash (`.bin`) log format.
///
/// The format is self-describing: FMT records (type `0x80`) carry the
/// layout of every other message type. Each message is framed by the
/// two-byte sync `0xA3 0x95` followed by a one-byte type id. Messages are
/// handed to a callback and not retained, so memory stays flat regardless
/// of log size.
enum DataFlashParser {
    static let head1: UInt8 = 0xA3
    static let head2: UInt8 = 0x95
    static let fmtType: UInt8 = 0x80
    static let fmtBodyLength = 86   // 1 + 1 + 4 + 16 + 64

    enum ParseError: Error { case unreadable }

    /// Decode `data`, invoking `handler` for each message whose name is in
    /// `wanted` (or every message when `wanted` is nil).
    static func parse(data: Data,
                      wanted: Set<String>? = nil,
                      handler: (LogMessage) -> Void) throws {
        let bytes = [UInt8](data)
        let n = bytes.count
        var formats: [UInt8: LogFormat] = [:]
        var i = 0

        while i + 3 <= n {
            guard bytes[i] == head1, bytes[i + 1] == head2 else {
                i += 1
                continue
            }
            let type = bytes[i + 2]
            let bodyStart = i + 3

            if type == fmtType {
                guard bodyStart + fmtBodyLength <= n else { break }
                let fmt = parseFMT(bytes, at: bodyStart)
                formats[fmt.type] = fmt
                i = bodyStart + fmtBodyLength
                continue
            }

            guard let fmt = formats[type] else {
                // Unknown type — likely a mis-sync. Step one byte and rescan.
                i += 1
                continue
            }
            let bodyLength = fmt.length - 3
            guard bodyLength >= 0, bodyStart + bodyLength <= n else { break }
            if wanted == nil || wanted!.contains(fmt.name) {
                handler(decode(bytes, at: bodyStart, format: fmt))
            }
            i = bodyStart + bodyLength
        }

        if formats.isEmpty { throw ParseError.unreadable }
    }

    // ── FMT record ───────────────────────────────────────────────────────
    private static func parseFMT(_ b: [UInt8], at o: Int) -> LogFormat {
        let type = b[o]
        let length = Int(b[o + 1])
        let name = cString(b, o + 2, 4)
        let format = cString(b, o + 6, 16)
        let columnList = cString(b, o + 22, 64)
        let columns = columnList.split(separator: ",").map(String.init)
        return LogFormat(type: type, length: length,
                         name: name, format: format, columns: columns)
    }

    // ── Body decode ──────────────────────────────────────────────────────
    private static func decode(_ b: [UInt8], at start: Int,
                               format: LogFormat) -> LogMessage {
        var fields: [String: LogValue] = [:]
        var off = start
        for (index, code) in format.format.enumerated() {
            let size = fieldSize(code)
            guard size > 0, off + size <= b.count else { break }
            let column = index < format.columns.count
                ? format.columns[index] : "f\(index)"
            fields[column] = readValue(code, b, off, size)
            off += size
        }
        return LogMessage(name: format.name, fields: fields)
    }

    /// Byte width of a DataFlash format character.
    private static func fieldSize(_ c: Character) -> Int {
        switch c {
        case "a":                          return 64   // int16[32]
        case "b", "B", "M":                return 1
        case "h", "H", "c", "C":           return 2
        case "n", "i", "I", "f", "e", "E", "L": return 4
        case "d", "q", "Q":                return 8
        case "N":                          return 16
        case "Z":                          return 64
        default:                           return 0
        }
    }

    private static func readValue(_ c: Character, _ b: [UInt8],
                                  _ o: Int, _ size: Int) -> LogValue {
        switch c {
        case "b":      return .int(Int64(Int8(bitPattern: b[o])))
        case "B", "M": return .uint(UInt64(b[o]))
        case "h":      return .int(Int64(Int16(bitPattern: u16(b, o))))
        case "H":      return .uint(UInt64(u16(b, o)))
        case "i", "L": return .int(Int64(Int32(bitPattern: u32(b, o))))
        case "I":      return .uint(UInt64(u32(b, o)))
        case "f":      return .double(Double(Float(bitPattern: u32(b, o))))
        case "d":      return .double(Double(bitPattern: u64(b, o)))
        case "q":      return .int(Int64(bitPattern: u64(b, o)))
        case "Q":      return .uint(u64(b, o))
        case "c":      return .double(Double(Int16(bitPattern: u16(b, o))) / 100)
        case "C":      return .double(Double(u16(b, o)) / 100)
        case "e":      return .double(Double(Int32(bitPattern: u32(b, o))) / 100)
        case "E":      return .double(Double(u32(b, o)) / 100)
        case "n", "N", "Z": return .string(cString(b, o, size))
        case "a":      return .int(0)   // int16[32] array — not consumed
        default:       return .uint(0)
        }
    }

    // ── Little-endian readers ────────────────────────────────────────────
    private static func u16(_ b: [UInt8], _ o: Int) -> UInt16 {
        UInt16(b[o]) | (UInt16(b[o + 1]) << 8)
    }

    private static func u32(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(b[o])
            | (UInt32(b[o + 1]) << 8)
            | (UInt32(b[o + 2]) << 16)
            | (UInt32(b[o + 3]) << 24)
    }

    private static func u64(_ b: [UInt8], _ o: Int) -> UInt64 {
        var v: UInt64 = 0
        for k in 0..<8 { v |= UInt64(b[o + k]) << (8 * k) }
        return v
    }

    private static func cString(_ b: [UInt8], _ o: Int, _ len: Int) -> String {
        var out: [UInt8] = []
        out.reserveCapacity(len)
        for k in 0..<len {
            let byte = b[o + k]
            if byte == 0 { break }
            out.append(byte)
        }
        return String(decoding: out, as: UTF8.self)
    }
}
