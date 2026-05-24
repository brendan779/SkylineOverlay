import Foundation
import Darwin

/// Thin POSIX wrapper around a `/dev/cu.*` USB-serial device.
///
/// Opens the device, configures `termios` for raw 8N1 at the requested baud,
/// and exposes the incoming byte stream as an `AsyncStream<Data>`. The reader
/// runs on a detached task and is torn down by `close()`.
final class Serial: @unchecked Sendable {
    enum SerialError: Error, LocalizedError {
        case open(String, Int32)
        case configure(String, Int32)

        var errorDescription: String? {
            switch self {
            case .open(let path, let err):
                return "Couldn't open \(path) — \(String(cString: strerror(err)))"
            case .configure(let path, let err):
                return "Couldn't configure \(path) — \(String(cString: strerror(err)))"
            }
        }
    }

    /// Common baud rates we offer in the picker.
    static let commonBaudRates: [Int] = [
        9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600,
    ]

    /// List of likely USB-serial device paths under `/dev`. Matches the
    /// patterns common adapters expose (FTDI, CP210x, CH34x, CDC-ACM, etc.).
    static func availablePorts() -> [String] {
        let prefixes = ["cu.usbserial", "cu.usbmodem", "cu.SLAB",
                        "cu.wchusbserial", "cu.UART", "cu.PL2303"]
        let entries = (try? FileManager.default
            .contentsOfDirectory(atPath: "/dev")) ?? []
        return entries
            .filter { name in prefixes.contains { name.hasPrefix($0) } }
            .map { "/dev/" + $0 }
            .sorted()
    }

    private var fd: Int32 = -1
    private var readTask: Task<Void, Never>?
    private let path: String

    init(path: String) { self.path = path }

    /// Open the device and return an async stream of incoming bytes.
    /// The stream terminates when `close()` is called or the device drops.
    func open(baud: Int) throws -> AsyncStream<Data> {
        let descriptor = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard descriptor >= 0 else {
            throw SerialError.open(path, errno)
        }

        var settings = termios()
        guard tcgetattr(descriptor, &settings) == 0 else {
            let err = errno
            Darwin.close(descriptor)
            throw SerialError.configure(path, err)
        }
        cfmakeraw(&settings)
        cfsetspeed(&settings, speed_t(baud))
        // 8N1, enable receive, ignore modem control lines.
        settings.c_cflag |= tcflag_t(CREAD | CLOCAL | CS8)
        settings.c_cflag &= ~tcflag_t(PARENB | CSTOPB)

        guard tcsetattr(descriptor, TCSANOW, &settings) == 0 else {
            let err = errno
            Darwin.close(descriptor)
            throw SerialError.configure(path, err)
        }

        // Keep O_NONBLOCK set — the read loop handles `EAGAIN` by sleeping.
        self.fd = descriptor

        let (stream, continuation) = AsyncStream<Data>.makeStream(
            of: Data.self,
            bufferingPolicy: .bufferingNewest(64))

        readTask = Task.detached { [descriptor] in
            var buffer = [UInt8](repeating: 0, count: 4096)
            while !Task.isCancelled {
                let n: Int = buffer.withUnsafeMutableBufferPointer { ptr in
                    Darwin.read(descriptor, ptr.baseAddress, ptr.count)
                }
                if n > 0 {
                    continuation.yield(Data(buffer.prefix(n)))
                } else if n == 0 {
                    // EOF on the device — telemetry radio unplugged.
                    break
                } else {
                    let err = errno
                    if err == EAGAIN || err == EWOULDBLOCK || err == EINTR {
                        try? await Task.sleep(nanoseconds: 5_000_000)
                        continue
                    }
                    break       // fatal — end the stream
                }
            }
            continuation.finish()
            Darwin.close(descriptor)
        }

        return stream
    }

    /// Cancel the read task and close the file descriptor.
    func close() {
        readTask?.cancel()
        readTask = nil
        // The detached task closes `fd` once it sees cancellation.
        fd = -1
    }
}
