import SwiftUI

// MARK: - Macro Color Manager
//
// Colours are stored as comma-separated RGBA float strings in UserDefaults,
// e.g. "1.0,0.584,0.0,1.0". This round-trips perfectly for any colour space
// the system ColorPicker can produce (sRGB, Display P3, etc.), avoiding the
// precision loss and gamut-clamping that hex strings cause.

struct MacroColorManager {

    // Default encoded values (sRGB floats)
    static let defaultCalHex  = colorToString(Color(red: 1.00, green: 0.58, blue: 0.00)) // amber
    static let defaultProtHex = colorToString(Color(red: 0.00, green: 0.48, blue: 1.00)) // blue
    static let defaultCarbHex = colorToString(Color(red: 1.00, green: 0.42, blue: 0.00)) // orange
    static let defaultFatHex  = colorToString(Color(red: 0.85, green: 0.70, blue: 0.10)) // gold

    /// Encode a Color → storable string. Uses extended sRGB so wide-gamut values are preserved.
    static func colorToString(_ color: Color) -> String {
        let ui = UIColor(color).cgColor.converted(
            to: CGColorSpace(name: CGColorSpace.extendedSRGB)!,
            intent: .defaultIntent,
            options: nil
        ) ?? UIColor(color).cgColor
        let c = ui.components ?? [0, 0, 0, 1]
        let r = c.count > 0 ? c[0] : 0
        let g = c.count > 1 ? c[1] : 0
        let b = c.count > 2 ? c[2] : 0
        let a = c.count > 3 ? c[3] : 1
        return "\(r),\(g),\(b),\(a)"
    }

    /// Decode a stored string → Color. Falls back to clear on malformed input.
    static func colorFromString(_ s: String) -> Color {
        let parts = s.split(separator: ",").compactMap { Double($0) }
        guard parts.count >= 3 else { return .clear }
        let a = parts.count >= 4 ? parts[3] : 1.0
        return Color(.displayP3, red: parts[0], green: parts[1], blue: parts[2], opacity: a)
    }
}

// MARK: - Convenience Color extension for AppStorage round-tripping

extension Color {
    /// Encode to a storable string (lossless, any colour space).
    var encodedString: String { MacroColorManager.colorToString(self) }

    /// Decode from a stored string.
    static func fromEncoded(_ s: String) -> Color { MacroColorManager.colorFromString(s) }
}
