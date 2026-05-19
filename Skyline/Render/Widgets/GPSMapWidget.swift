import SwiftUI

/// GPS map — the flown flight path drawn over a cached MapKit snapshot of the
/// whole flight. A zoomed viewport pans across the snapshot to keep the
/// moving dot centred on the aircraft during playback. Only the path already
/// flown (up to the playhead) is drawn — never the future route.
struct GPSMapWidget: View {
    var settings: WidgetSettings
    var theme: OverlayTheme
    var snapshot: FlightMapImage?
    var track: [TrackPoint]
    var currentTime: Double
    var currentCoord: GeoPoint?
    var home: GeoPoint?
    /// Recent-trail length in seconds; 0 draws the whole flown path.
    var trailSeconds: Double
    /// Display zoom — 1 fits the whole flight, higher zooms in and follows.
    var zoom: Double
    var size: CGSize

    var body: some View {
        Canvas { ctx, sz in draw(&ctx, sz) }
            .frame(width: size.width, height: size.height)
    }

    private func draw(_ ctx: inout GraphicsContext, _ sz: CGSize) {
        let w = sz.width, h = sz.height
        let accent = settings.accent.color

        let panel = Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h),
                         cornerRadius: h * 0.07)

        guard let snapshot, !track.isEmpty else {
            ctx.fill(panel, with: .color(settings.background.color))
            ctx.stroke(panel, with: .color(.white.opacity(0.22)), lineWidth: 1)
            let note = track.isEmpty ? "NO GPS DATA" : "MAP LOADING…"
            ctx.draw(Text(note).font(.hud(h * 0.09))
                        .foregroundStyle(theme.label.color),
                     at: CGPoint(x: w / 2, y: h / 2), anchor: .center)
            return
        }

        ctx.clip(to: panel)

        let imageSize = snapshot.image.size
        func onImage(_ p: GeoPoint) -> CGPoint {
            snapshot.point(for: p, in: imageSize)
        }

        // The viewport is a window onto the snapshot image: shrunk by `zoom`
        // and centred on the aircraft, clamped so it never leaves the image.
        let z = max(1, zoom)
        let vpW = imageSize.width / z
        let vpH = imageSize.height / z
        let focus = currentCoord.map { onImage($0) }
            ?? CGPoint(x: imageSize.width / 2, y: imageSize.height / 2)
        let vpX = min(max(focus.x - vpW / 2, 0), max(0, imageSize.width - vpW))
        let vpY = min(max(focus.y - vpH / 2, 0), max(0, imageSize.height - vpH))
        let scale = vpW > 0 ? w / vpW : 1

        func project(_ p: GeoPoint) -> CGPoint {
            let pt = onImage(p)
            return CGPoint(x: (pt.x - vpX) * scale, y: (pt.y - vpY) * scale)
        }

        // Map image, panned and scaled into the viewport.
        ctx.draw(Image(nsImage: snapshot.image),
                 in: CGRect(x: -vpX * scale, y: -vpY * scale,
                            width: imageSize.width * scale,
                            height: imageSize.height * scale))
        // Darken slightly so the path and dot stay legible.
        ctx.fill(panel, with: .color(.black.opacity(0.12)))

        // Path already flown: from the trail start (or track start) up to the
        // playhead — future track points are never drawn.
        let endIdx = track.firstIndex { $0.t > currentTime } ?? track.count
        let startIdx: Int
        if trailSeconds > 0 {
            let cutoff = currentTime - trailSeconds
            startIdx = track.firstIndex { $0.t >= cutoff } ?? endIdx
        } else {
            startIdx = 0
        }
        var points = (startIdx < endIdx ? track[startIdx..<endIdx] : [])
            .map { project($0.point) }
        // Extend the line to the interpolated playhead so it meets the dot.
        if let currentCoord { points.append(project(currentCoord)) }
        if points.count >= 2 {
            var line = Path()
            line.move(to: points[0])
            for p in points.dropFirst() { line.addLine(to: p) }
            ctx.stroke(line, with: .color(accent),
                       style: StrokeStyle(lineWidth: max(2, h * 0.016),
                                          lineCap: .round, lineJoin: .round))
        }

        // Home marker.
        if let home {
            let p = project(home)
            let r = h * 0.022
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r,
                                            width: r * 2, height: r * 2)),
                     with: .color(.white))
            ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r * 1.8, y: p.y - r * 1.8,
                                              width: r * 3.6, height: r * 3.6)),
                       with: .color(.white.opacity(0.6)), lineWidth: 1)
        }

        // Moving dot at the playhead.
        if let currentCoord {
            let p = project(currentCoord)
            let r = h * 0.032
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 1.7, y: p.y - r * 1.7,
                                            width: r * 3.4, height: r * 3.4)),
                     with: .color(accent.opacity(0.3)))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r,
                                            width: r * 2, height: r * 2)),
                     with: .color(accent))
            ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r,
                                              width: r * 2, height: r * 2)),
                       with: .color(.white), lineWidth: max(1, h * 0.008))
        }

        ctx.stroke(panel, with: .color(.white.opacity(0.22)), lineWidth: 1)
    }
}
