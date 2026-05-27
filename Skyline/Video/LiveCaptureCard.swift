import Foundation
import AVFoundation
import Observation

/// Live video from a USB UVC capture card (or any other macOS-visible
/// `AVCaptureDevice` video source). Uses AVFoundation directly — no
/// external dependencies, sub-100ms latency, and Cosmostreamer's USB-C
/// capture path is already verified working end-to-end.
@MainActor
@Observable
final class LiveCaptureCard {

    enum Status: Equatable {
        case disconnected
        case connecting(deviceName: String)
        case playing(deviceName: String)
        case failed(String)
    }

    var status: Status = .disconnected
    /// Unique ID of the device most recently asked to connect (whether or
    /// not it succeeded) — restored from UserDefaults at sheet open time.
    var lastDeviceID: String = ""

    /// The underlying capture session. Public so `CaptureCardNSView` can
    /// attach its preview layer.
    let session = AVCaptureSession()

    private var currentInput: AVCaptureDeviceInput?

    /// All discoverable video capture devices — built-in cameras and
    /// external USB UVC capture devices.
    static func availableDevices() -> [AVCaptureDevice] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified)
        return discovery.devices
    }

    var isPlaying: Bool {
        if case .playing = status { return true }
        return false
    }

    func connect(device: AVCaptureDevice) {
        disconnect()
        lastDeviceID = device.uniqueID
        UserDefaults.standard.set(device.uniqueID,
                                  forKey: "Skyline.captureCard.deviceID")
        status = .connecting(deviceName: device.localizedName)

        do {
            let input = try AVCaptureDeviceInput(device: device)
            session.beginConfiguration()
            session.sessionPreset = .high
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                status = .failed("Can't open \(device.localizedName) — "
                                 + "already in use by another app?")
                return
            }
            session.addInput(input)
            currentInput = input
            session.commitConfiguration()

            // startRunning() blocks while AVFoundation negotiates with the
            // device — run it off-main so the UI stays responsive.
            let name = device.localizedName
            Task.detached { [session] in
                session.startRunning()
                await MainActor.run {
                    self.status = .playing(deviceName: name)
                }
            }
        } catch {
            status = .failed("Couldn't open device — \(error.localizedDescription)")
        }
    }

    func disconnect() {
        if session.isRunning {
            session.stopRunning()
        }
        session.beginConfiguration()
        if let input = currentInput {
            session.removeInput(input)
        }
        currentInput = nil
        session.commitConfiguration()
        status = .disconnected
    }
}
