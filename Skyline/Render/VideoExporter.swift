import AVFoundation
import SwiftUI
import CoreVideo
import MapKit

/// Renders the overlay to a transparent video file.
///
/// Each frame is rasterised from `OverlayView` via `ImageRenderer` and
/// appended to an `AVAssetWriter`. ProRes 4444 preserves the alpha channel,
/// so the result composites directly over footage in any editor.
@MainActor
final class VideoExporter {
    struct Progress {
        var frame: Int
        var total: Int
        var fraction: Double { total > 0 ? Double(frame) / Double(total) : 0 }
    }

    enum ExportError: LocalizedError {
        case setupFailed
        case pixelBufferFailed
        case renderFailed
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .setupFailed:        return "Couldn't initialise the video writer."
            case .pixelBufferFailed:  return "Couldn't allocate a video frame buffer."
            case .renderFailed:       return "Couldn't rasterise an overlay frame."
            case .writeFailed(let m): return "Video writing failed: \(m)"
            }
        }
    }

    private var cancelled = false

    func cancel() { cancelled = true }

    /// Export the overlay for `log` to `url`.
    ///
    /// `startTime` shifts the export window forward on the scrub timeline
    /// (used to render a marked in/out range). `duration` sets the export
    /// length (the video's length when one is loaded); nil uses the log's
    /// length. `timeOffset` shifts the telemetry so the exported overlay
    /// lines up with the footage.
    func export(log: FlightLog, config: OverlayConfig, to url: URL,
                startTime: Double = 0,
                duration: Double? = nil,
                timeOffset: Double = 0,
                mapSnapshot: FlightMapImage? = nil,
                progress: @escaping (Progress) -> Void) async throws {
        cancelled = false
        let out = config.output
        let width = out.width, height = out.height
        let fps = out.fps
        let totalDuration = duration ?? log.duration()
        let totalFrames = max(1, Int(totalDuration * fps))

        try? FileManager.default.removeItem(at: url)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else {
            throw ExportError.setupFailed
        }

        let codec: AVVideoCodecType
        switch out.codec {
        case .proRes4444:  codec = .proRes4444
        case .proRes422HQ: codec = .proRes422HQ
        case .h264:        codec = .h264
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ])

        guard writer.canAdd(input) else { throw ExportError.setupFailed }
        writer.add(input)
        guard writer.startWriting() else {
            throw ExportError.writeFailed(
                writer.error?.localizedDescription ?? "could not start writing")
        }
        writer.startSession(atSourceTime: .zero)

        let timescale = CMTimeScale(fps.rounded())
        for frame in 0..<totalFrames {
            if cancelled {
                writer.cancelWriting()
                throw CancellationError()
            }
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 8_000_000)
            }
            let telemetryTime = min(
                max(Double(frame) / fps + startTime + timeOffset, 0),
                log.duration())
            let sample = TelemetrySample.make(from: log, at: telemetryTime,
                                              config: config)
            let buffer = try renderFrame(config: config, sample: sample,
                                         mapSnapshot: mapSnapshot,
                                         width: width, height: height,
                                         pool: adaptor.pixelBufferPool)
            let pts = CMTime(value: CMTimeValue(frame), timescale: timescale)
            guard adaptor.append(buffer, withPresentationTime: pts) else {
                writer.cancelWriting()
                throw ExportError.writeFailed(
                    writer.error?.localizedDescription ?? "frame append failed")
            }
            progress(Progress(frame: frame + 1, total: totalFrames))
            await Task.yield()
        }

        input.markAsFinished()
        await writer.finishWriting()
        if writer.status == .failed {
            throw ExportError.writeFailed(
                writer.error?.localizedDescription ?? "unknown error")
        }
    }

    // ── Frame rasterisation ──────────────────────────────────────────────
    private func renderFrame(config: OverlayConfig, sample: TelemetrySample,
                             mapSnapshot: FlightMapImage?,
                             width: Int, height: Int,
                             pool: CVPixelBufferPool?) throws -> CVPixelBuffer {
        let view = OverlayView(config: config, sample: sample,
                               frameSize: CGSize(width: width, height: height),
                               mapSnapshot: mapSnapshot)
        let renderer = ImageRenderer(content: view)
        renderer.isOpaque = false
        renderer.scale = 1
        guard let cgImage = renderer.cgImage else { throw ExportError.renderFailed }

        var maybeBuffer: CVPixelBuffer?
        if let pool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &maybeBuffer)
        }
        guard let buffer = maybeBuffer else { throw ExportError.pixelBufferFailed }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue)
        else { throw ExportError.pixelBufferFailed }

        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}
