import Foundation

/// The telemetry widgets the overlay can draw.
///
/// The case order is the back-to-front draw order used by the renderer and
/// the order widgets appear in the Inspector.
enum WidgetKind: String, CaseIterable, Codable, Identifiable {
    case groundSpeed
    case airSpeed
    case altitude
    case wind
    case attitude
    case heading
    case verticalSpeed
    case motors
    case rangefinder
    case flightMode
    case messages

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .groundSpeed:   return "Ground Speed"
        case .airSpeed:      return "Airspeed"
        case .altitude:      return "Altitude"
        case .wind:          return "Wind Compass"
        case .attitude:      return "Artificial Horizon"
        case .heading:       return "Heading Compass"
        case .verticalSpeed: return "Vertical Speed"
        case .motors:        return "Motors"
        case .rangefinder:   return "Rangefinder"
        case .flightMode:    return "Flight Mode"
        case .messages:      return "Messages"
        }
    }

    /// Native size in design points at a 1920×1080 reference frame, scale 1.0.
    /// The renderer multiplies this by the output scale and the widget's own
    /// `scale`; `position` places the centre of a box this size.
    var designSize: CGSize {
        switch self {
        case .groundSpeed, .airSpeed, .altitude:
            return CGSize(width: 150, height: 150)
        case .wind:
            return CGSize(width: 150, height: 150)
        case .attitude:
            return CGSize(width: 250, height: 150)
        case .heading:
            return CGSize(width: 250, height: 34)
        case .verticalSpeed:
            return CGSize(width: 60, height: 150)
        case .motors:
            return CGSize(width: 150, height: 150)
        case .rangefinder:
            return CGSize(width: 120, height: 70)
        case .flightMode:
            return CGSize(width: 190, height: 46)
        case .messages:
            return CGSize(width: 360, height: 90)
        }
    }
}
