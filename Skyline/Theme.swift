import SwiftUI

/// Design tokens from the Skyline handoff. Chrome only — the preview/overlay
/// content comes from the Python renderer, not from these.
enum Theme {
    // Surfaces
    static let appBackground = Color(hex: 0x0E1013)
    static let surface = Color(hex: 0x16181B)
    static let previewBackground = Color(hex: 0x0A0C0E)

    // Borders
    static let border = Color.white.opacity(0.06)
    static let borderStrong = Color.white.opacity(0.12)

    // Text
    static let textPrimary = Color(hex: 0xE8EAED)
    static let textSecondary = Color.white.opacity(0.70)
    static let textTertiary = Color.white.opacity(0.55)
    static let textMuted = Color.white.opacity(0.40)

    // Accent — default DJI Mavic green
    static let accent = Color(hex: 0x41D77D)

    // Error
    static let error = Color(hex: 0xFF5A5A)
    static let errorText = Color(hex: 0xFF7A7A)

    // Traffic lights
    static let trafficRed = Color(hex: 0xFF5F57)
    static let trafficYellow = Color(hex: 0xFEBC2E)
    static let trafficGreen = Color(hex: 0x28C840)

    // Layout
    static let sidebarWidth: CGFloat = 232
    static let inspectorWidth: CGFloat = 320
    static let titleBarHeight: CGFloat = 36
    static let minWindowSize = CGSize(width: 1280, height: 800)
    static let defaultWindowSize = CGSize(width: 1400, height: 860)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
