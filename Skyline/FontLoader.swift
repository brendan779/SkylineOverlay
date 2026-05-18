import Foundation
import CoreText

/// Registers the bundled Barlow Condensed fonts so the HUD renders with the
/// same typography as the design (and offline, without relying on a system
/// font being installed). Call once at launch.
enum FontLoader {
    static func registerBundledFonts() {
        let faces = [
            "BarlowCondensed-Regular",
            "BarlowCondensed-Medium",
            "BarlowCondensed-Bold",
        ]
        for face in faces {
            guard let url = Bundle.main.url(forResource: face, withExtension: "ttf")
            else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
