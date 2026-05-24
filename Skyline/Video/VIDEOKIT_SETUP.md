# Wiring up VLCKit for live RTSP video

Skyline ships with the live‑video architecture in place but **without**
the VLCKit framework — adding a binary package via SwiftPM is a one‑time
Xcode step rather than something Skyline can do automatically. Until
VLCKit is added, the "Connect Video Stream" UI shows a placeholder and
`canImport(VLCKit)` is false everywhere.

## Add the dependency (~30 seconds, one time)

VideoLAN's own `code.videolan.org/videolan/VLCKit.git` is **not** SPM-
compatible — it has no `Package.swift`. Use one of the community wrappers
instead:

1. Open `Skyline.xcodeproj` in Xcode.
2. **File → Add Package Dependencies…**
3. Paste: `https://github.com/tylerjonesio/vlckit-spm`
   - Stable VLCKit 3.5.x distribution. Recommended.
   - Newer alternative (VLCKit 4 alpha + PiP):
     `https://github.com/virtualox/vlckit-spm`
4. Click **Add Package** with "Up to Next Major" version rule.
5. In the products sheet, tick **VLCKit** for the **Skyline** target,
   then **Add Package**.
6. Build. The placeholder disappears and live RTSP playback starts
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
