import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// Canary's colours, from Apple's system palette.
//
// Red, orange and green mean attention levels and nothing else (charter §6), so
// domains take their colours from the rest of the palette, the way Health gives
// each category its own colour. Every colour has a fill (bright, for charts,
// icons and washes) and a text variant (Apple's increased-contrast value, which
// keeps text at WCAG AA on light and dark backgrounds).

/// A fill colour and a text colour that belong together.
public struct Hue: Sendable {
    public let fill: Color
    public let text: Color

    public init(fill: Color, text: Color) {
        self.fill = fill
        self.text = text
    }

    init(light: UInt32, dark: UInt32, textLight: UInt32, textDark: UInt32) {
        fill = Color(light: light, dark: dark)
        text = Color(light: textLight, dark: textDark)
    }
}

extension Color {
    /// A colour with separate light and dark appearances, as `0xRRGGBB`.
    public init(light: UInt32, dark: UInt32) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
        #else
        self.init(red: Double((light >> 16) & 0xFF) / 255, green: Double((light >> 8) & 0xFF) / 255,
                  blue: Double(light & 0xFF) / 255)
        #endif
    }
}

// MARK: - Levels

extension Level {
    /// Fill and text colours: Apple's red, orange and green, and their
    /// increased-contrast variants for text.
    public var hue: Hue {
        switch self {
        case .alert: Hue(light: 0xFF3B30, dark: 0xFF453A, textLight: 0xD70015, textDark: 0xFF6961)
        case .watch: Hue(light: 0xFF9500, dark: 0xFF9F0A, textLight: 0xC93400, textDark: 0xFFB340)
        case .normal: Hue(light: 0x34C759, dark: 0x30D158, textLight: 0x248A3D, textDark: 0x30DB5B)
        case .stale, .pending: Hue(light: 0x8E8E93, dark: 0x8E8E93, textLight: 0x6C6C70, textDark: 0xAEAEB2)
        }
    }

    /// Text in the level's colour, readable at body sizes.
    public var textColor: Color { hue.text }
}

// MARK: - Domains

extension DomainStyle {
    /// Each domain's colour, as Health colours its categories.
    public static func hue(for id: String) -> Hue {
        switch id {
        case "markets": Hue(light: 0x007AFF, dark: 0x0A84FF, textLight: 0x0040DD, textDark: 0x409CFF)
        case "economy": Hue(light: 0x5856D6, dark: 0x5E5CE6, textLight: 0x3634A3, textDark: 0x7D7AFF)
        case "energy": Hue(light: 0x30B0C7, dark: 0x40C8E0, textLight: 0x008299, textDark: 0x5DE6FF)
        case "geopolitics": Hue(light: 0xAF52DE, dark: 0xBF5AF2, textLight: 0x8944AB, textDark: 0xDA8FFF)
        case "conflict": Hue(light: 0xA2845E, dark: 0xAC8E68, textLight: 0x7F6545, textDark: 0xB59469)
        case "hazards": Hue(light: 0x32ADE6, dark: 0x64D2FF, textLight: 0x0071A4, textDark: 0x70D7FF)
        case "climate": Hue(light: 0x00C7BE, dark: 0x63E6E2, textLight: 0x0C817B, textDark: 0x66D4CF)
        case "health": Hue(light: 0xE0479E, dark: 0xF06AB8, textLight: 0xB0257A, textDark: 0xFF8CCB)
        case "tech": Hue(light: 0x5B7C99, dark: 0x8AA9C4, textLight: 0x3E5A73, textDark: 0xA9C2D6)
        case "humanitarian": Hue(light: 0x8E7CC3, dark: 0xA899E0, textLight: 0x5E4C99, textDark: 0xC4B8F0)
        case "uk": Hue(light: 0x6E6E73, dark: 0x98989D, textLight: 0x48484A, textDark: 0xAEAEB2)
        default: Hue(light: 0x007AFF, dark: 0x0A84FF, textLight: 0x0040DD, textDark: 0x409CFF)
        }
    }

    public static func color(for id: String) -> Color { hue(for: id).fill }
}

// MARK: - Basis

extension Basis {
    /// Not attention colours: how a level was set is a different question.
    public var hue: Hue {
        switch self {
        case .measured: Hue(light: 0x007AFF, dark: 0x0A84FF, textLight: 0x0040DD, textDark: 0x409CFF)
        case .published: Hue(light: 0x30B0C7, dark: 0x40C8E0, textLight: 0x008299, textDark: 0x5DE6FF)
        case .judged: Hue(light: 0xAF52DE, dark: 0xBF5AF2, textLight: 0x8944AB, textDark: 0xDA8FFF)
        case .unknown: Hue(light: 0x8E8E93, dark: 0x8E8E93, textLight: 0x6C6C70, textDark: 0xAEAEB2)
        }
    }
}

// MARK: - World State bands

extension WorldBand {
    /// Pastel colours for a 3 × 3 mesh gradient behind the World State, in the
    /// band's attention colours (Calm is cool, Severe is warm).
    public var meshColors: [Color] {
        let (a, b, c): (Color, Color, Color) = switch self {
        case .calm: (.mint, .teal, .cyan)
        case .unsettled: (.yellow, .mint, .orange)
        case .strained: (.orange, .pink, .yellow)
        case .severe: (.red, .pink, .orange)
        case .unknown: (.gray, .gray, .gray)
        }
        return [
            a.opacity(0.24), b.opacity(0.17), c.opacity(0.12),
            b.opacity(0.15), a.opacity(0.17), b.opacity(0.10),
            c.opacity(0.11), b.opacity(0.09), a.opacity(0.05),
        ]
    }

    /// Colours along the score ring, cool to warm up to the band.
    public var ringColors: [Color] {
        switch self {
        case .calm: [.mint, .teal]
        case .unsettled: [.mint, .yellow, .orange]
        case .strained: [.yellow, .orange, .pink]
        case .severe: [.orange, .pink, .red]
        case .unknown: [.gray, .gray]
        }
    }
}
