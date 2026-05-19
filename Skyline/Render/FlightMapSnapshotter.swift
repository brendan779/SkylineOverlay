import MapKit
import AppKit

extension FlightMapStyle {
    /// The MapKit configuration that renders this style.
    var configuration: MKMapConfiguration {
        switch self {
        case .standard:  return MKStandardMapConfiguration()
        case .satellite: return MKImageryMapConfiguration()
        case .hybrid:    return MKHybridMapConfiguration()
        }
    }
}

/// Normalised Web Mercator projection — the same projection MapKit renders
/// tiles in. Both axes are 0…1 over the whole world, so a region whose
/// `x`/`y` extents match an image's aspect ratio renders undistorted.
enum Mercator {
    static func x(_ lon: Double) -> Double { (lon + 180) / 360 }

    static func y(_ lat: Double) -> Double {
        let rad = min(max(lat, -85), 85) * .pi / 180
        return 0.5 - log(tan(.pi / 4 + rad / 2)) / (2 * .pi)
    }

    static func lon(_ x: Double) -> Double { x * 360 - 180 }

    static func lat(_ y: Double) -> Double {
        (2 * atan(exp((0.5 - y) * 2 * .pi)) - .pi / 2) * 180 / .pi
    }
}

/// A rendered map image plus the Web Mercator bounds it covers. The GPS Map
/// widget projects coordinates onto it directly, with a known top-left
/// origin, so the flight path lines up exactly with the map tiles.
struct FlightMapImage {
    let image: NSImage
    /// Normalised Web Mercator bounds of the rendered area.
    let xMin: Double, xMax: Double
    let yMin: Double, yMax: Double

    /// Project a coordinate to a point in an image of `size` (top-left origin).
    func point(for p: GeoPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: (Mercator.x(p.longitude) - xMin) / (xMax - xMin) * size.width,
                y: (Mercator.y(p.latitude) - yMin) / (yMax - yMin) * size.height)
    }
}

/// Renders a static map image covering the whole flight.
///
/// MapKit tiles load asynchronously and can't be rasterised inside the
/// `ImageRenderer` export pass, so the map is snapshotted once up front. The
/// GPS Map widget then composites the path on top and pans a zoomed viewport
/// across the image to follow the aircraft — no per-frame re-snapshotting.
enum FlightMapSnapshotter {

    @MainActor
    static func snapshot(track: [TrackPoint], style: FlightMapStyle,
                         size: CGSize) async -> FlightMapImage? {
        guard !track.isEmpty else { return nil }

        var minLat = Double.infinity, maxLat = -Double.infinity
        var minLon = Double.infinity, maxLon = -Double.infinity
        for p in track {
            minLat = min(minLat, p.point.latitude)
            maxLat = max(maxLat, p.point.latitude)
            minLon = min(minLon, p.point.longitude)
            maxLon = max(maxLon, p.point.longitude)
        }
        // Pad the geographic bounds so the path never touches the edge.
        let latPad = max((maxLat - minLat) * 0.15, 0.0008)
        let lonPad = max((maxLon - minLon) * 0.15, 0.0008)
        minLat -= latPad; maxLat += latPad
        minLon -= lonPad; maxLon += lonPad

        // Mercator bounds, then expand the short axis to the image aspect so
        // MapKit renders exactly this region without adjusting it.
        var xMin = Mercator.x(minLon), xMax = Mercator.x(maxLon)
        var yMin = Mercator.y(maxLat), yMax = Mercator.y(minLat)
        let xc = (xMin + xMax) / 2, yc = (yMin + yMax) / 2
        var halfX = (xMax - xMin) / 2, halfY = (yMax - yMin) / 2
        let target = size.width / size.height
        if halfX / halfY < target { halfX = halfY * target }
        else { halfY = halfX / target }
        xMin = xc - halfX; xMax = xc + halfX
        yMin = yc - halfY; yMax = yc + halfY

        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: Mercator.lat(yc),
                                           longitude: Mercator.lon(xc)),
            span: MKCoordinateSpan(
                latitudeDelta: Mercator.lat(yMin) - Mercator.lat(yMax),
                longitudeDelta: Mercator.lon(xMax) - Mercator.lon(xMin)))

        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = size
        options.preferredConfiguration = style.configuration
        options.showsBuildings = true
        guard let snap = try? await MKMapSnapshotter(options: options).start()
        else { return nil }
        return FlightMapImage(image: snap.image,
                              xMin: xMin, xMax: xMax, yMin: yMin, yMax: yMax)
    }
}
