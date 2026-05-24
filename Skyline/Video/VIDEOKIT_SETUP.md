# Wiring up VLCKit for live RTSP video

Skyline ships with the live‑video architecture in place but **without**
the VLCKit framework — adding a binary package via SwiftPM is a one‑time
Xcode step rather than something Skyline can do automatically. Until
VLCKit is added, the "Connect Video Stream" UI shows a placeholder and
`canImport(VLCKit)` is false everywhere.

## Add the dependency (one minute, one time)

1. Open `Skyline.xcodeproj` in Xcode.
2. **File → Add Package Dependencies…**
3. Paste a VLCKit package URL:
   - VideoLAN official (preferred):
     `https://code.videolan.org/videolan/VLCKit.git`
   - or a maintained SPM mirror, e.g. one of:
     - `https://github.com/Tim-Beals/VLCKit`
     - `https://github.com/mhmiles/VLCKit-SPM`
   The official package may not be SPM-compatible on every version — if
   the resolve step fails, switch to one of the mirrors.
4. Pick the **VLCKit** (or **MobileVLCKit** on iOS) product and add it to
   the **Skyline** target.
5. Build. The placeholder disappears and live RTSP playback starts
   working — no Skyline-side code changes needed.

## How to test against Cosmostreamer

Default URL pre-filled in the connect sheet: `rtsp://192.168.50.1:554/video`
— matches a Cosmostreamer Pi on the user's home network.

VLC options Skyline sets for low latency:

    :network-caching=200
    :live-caching=200
    :rtsp-tcp

Tune in `LiveVideoStream.swift` if your Pi feed feels laggy or stutters.

## Fallback: bundle as a manual framework

If SwiftPM keeps failing, download a binary build of VLCKit from
[VideoLAN's nightly artifacts](https://artifacts.videolan.org/VLCKit/)
and drag the `.xcframework` into the Xcode project, **Embed & Sign**.
The Skyline code uses `#if canImport(VLCKit)` so no code changes are
needed either way.
