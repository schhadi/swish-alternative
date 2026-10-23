import SwiftUI
import UIKit

// Quid colour tokens — docs/SPEC.md section 8.
// Light values are the spec's; dark mode inverts the surfaces and keeps the accent.

/// The colour tokens as UIKit dynamic colours. `Color` tokens below wrap these; tests resolve them in both appearances
/// to check contrast (QuidAppTests/DesignSystemTests.swift).
enum QuidPalette {
    static let background = UIColor.quidDynamic(light: 0xF6F7F5, dark: 0x111614)
    static let surface = UIColor.quidDynamic(light: 0xFFFFFF, dark: 0x1B2220)
    static let surfaceSecondary = UIColor.quidDynamic(light: 0xEEF1EF, dark: 0x27302C)
    static let surfaceSecondaryPressed = UIColor.quidDynamic(light: 0xDFE4E1, dark: 0x323C37)
    static let hairline = UIColor.quidDynamic(light: 0xEDF0EE, dark: 0x2A3330)

    static let ink = UIColor.quidDynamic(light: 0x141A17, dark: 0xF2F5F3)
    static let muted = UIColor.quidDynamic(light: 0x5F6B66, dark: 0x9BA7A1)

    static let accent = UIColor(quidHex: 0x0B6B54)
    static let accentPressed = UIColor(quidHex: 0x084D3D)
    static let onAccent = UIColor.white
    static let accentText = UIColor.quidDynamic(light: 0x0B6B54, dark: 0x6CCBAA)

    static let successTint = UIColor.quidDynamic(light: 0xE3F3EC, dark: 0x163A2E)
    static let successText = UIColor.quidDynamic(light: 0x084D3D, dark: 0xA3E4C8)
    static let pendingTint = UIColor.quidDynamic(light: 0xFDF1DF, dark: 0x3E2C12)
    static let pendingText = UIColor.quidDynamic(light: 0x9A5A12, dark: 0xF3C27B)
    static let failureTint = UIColor.quidDynamic(light: 0xFBE8E6, dark: 0x3F1E1A)
    static let failureText = UIColor.quidDynamic(light: 0x9A2B1F, dark: 0xF3A89D)
}

extension Color {
    /// A colour that resolves differently in light and dark appearance.
    static func quidDynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor.quidDynamic(light: light, dark: dark))
    }

    // MARK: Surfaces

    static let quidBackground = Color(uiColor: QuidPalette.background)
    static let quidSurface = Color(uiColor: QuidPalette.surface)
    /// Secondary fills: secondary buttons, keypad keys, icon tiles.
    static let quidSurfaceSecondary = Color(uiColor: QuidPalette.surfaceSecondary)
    /// Pressed state for secondary fills: visibly darker than resting, still neutral.
    static let quidSurfaceSecondaryPressed = Color(uiColor: QuidPalette.surfaceSecondaryPressed)
    static let quidHairline = Color(uiColor: QuidPalette.hairline)

    // MARK: Text

    static let quidInk = Color(uiColor: QuidPalette.ink)
    static let quidMuted = Color(uiColor: QuidPalette.muted)

    // MARK: Accent (identical in both appearances)

    static let quidAccent = Color(uiColor: QuidPalette.accent)
    static let quidAccentPressed = Color(uiColor: QuidPalette.accentPressed)
    static let quidOnAccent = Color(uiColor: QuidPalette.onAccent)
    /// Accent for small text and icons. Lightened in dark mode so it keeps 4.5:1 against dark surfaces.
    static let quidAccentText = Color(uiColor: QuidPalette.accentText)

    // MARK: Status

    static let quidSuccessTint = Color(uiColor: QuidPalette.successTint)
    static let quidSuccessText = Color(uiColor: QuidPalette.successText)
    static let quidPendingTint = Color(uiColor: QuidPalette.pendingTint)
    static let quidPendingText = Color(uiColor: QuidPalette.pendingText)
    static let quidFailureTint = Color(uiColor: QuidPalette.failureTint)
    static let quidFailureText = Color(uiColor: QuidPalette.failureText)
}

extension UIColor {
    /// A colour that resolves differently in light and dark appearance.
    static func quidDynamic(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(quidHex: dark) : UIColor(quidHex: light)
        }
    }

    convenience init(quidHex hex: UInt32) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }
}

/// Background/foreground pair for initials avatars. Picked deterministically from the name.
struct AvatarTint: Hashable {
    let backgroundColor: UIColor
    let foregroundColor: UIColor

    var background: Color { Color(uiColor: backgroundColor) }
    var foreground: Color { Color(uiColor: foregroundColor) }

    private init(background: (light: UInt32, dark: UInt32), foreground: (light: UInt32, dark: UInt32)) {
        backgroundColor = .quidDynamic(light: background.light, dark: background.dark)
        foregroundColor = .quidDynamic(light: foreground.light, dark: foreground.dark)
    }

    static let all: [AvatarTint] = [
        AvatarTint(background: (0xDCEBE3, 0x1F4A3C), foreground: (0x0B6B54, 0xA3E4C8)),
        AvatarTint(background: (0xF3E7D3, 0x4A3719), foreground: (0x7A4E10, 0xF3C27B)),
        AvatarTint(background: (0xDDE8F3, 0x1E3A52), foreground: (0x1F4E79, 0xA9CDEE)),
        AvatarTint(background: (0xE6E1F2, 0x332A52), foreground: (0x4B3A82, 0xC9BDF0)),
        AvatarTint(background: (0xF5E1E4, 0x4F2630), foreground: (0x8A2F45, 0xF2B4C2)),
        AvatarTint(background: (0xD9F0EA, 0x16433A), foreground: (0x0B5A4A, 0x9FE0CF)),
    ]

    /// Stable across launches (unlike `hashValue`).
    static func tint(for name: String) -> AvatarTint {
        var hash: UInt32 = 2_166_136_261
        for byte in name.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return all[Int(hash % UInt32(all.count))]
    }
}
