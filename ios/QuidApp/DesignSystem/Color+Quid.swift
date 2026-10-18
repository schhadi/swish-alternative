import SwiftUI
import UIKit

// Quid colour tokens — docs/SPEC.md section 8.
// Light values are the spec's; dark mode inverts the surfaces and keeps the accent.

extension Color {
    /// A colour that resolves differently in light and dark appearance.
    static func quidDynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(quidHex: dark) : UIColor(quidHex: light)
        })
    }

    // MARK: Surfaces

    static let quidBackground = quidDynamic(light: 0xF6F7F5, dark: 0x111614)
    static let quidSurface = quidDynamic(light: 0xFFFFFF, dark: 0x1B2220)
    /// Secondary fills: secondary buttons, keypad keys, icon tiles.
    static let quidSurfaceSecondary = quidDynamic(light: 0xEEF1EF, dark: 0x27302C)
    static let quidHairline = quidDynamic(light: 0xEDF0EE, dark: 0x2A3330)

    // MARK: Text

    static let quidInk = quidDynamic(light: 0x141A17, dark: 0xF2F5F3)
    static let quidMuted = quidDynamic(light: 0x5F6B66, dark: 0x9BA7A1)

    // MARK: Accent (identical in both appearances)

    static let quidAccent = Color(uiColor: UIColor(quidHex: 0x0B6B54))
    static let quidAccentPressed = Color(uiColor: UIColor(quidHex: 0x084D3D))
    static let quidOnAccent = Color.white
    /// Accent for small text and icons. Lightened in dark mode so it keeps 4.5:1 against dark surfaces.
    static let quidAccentText = quidDynamic(light: 0x0B6B54, dark: 0x6CCBAA)

    // MARK: Status

    static let quidSuccessTint = quidDynamic(light: 0xE3F3EC, dark: 0x163A2E)
    static let quidSuccessText = quidDynamic(light: 0x084D3D, dark: 0xA3E4C8)
    static let quidPendingTint = quidDynamic(light: 0xFDF1DF, dark: 0x3E2C12)
    static let quidPendingText = quidDynamic(light: 0x9A5A12, dark: 0xF3C27B)
    static let quidFailureTint = quidDynamic(light: 0xFBE8E6, dark: 0x3F1E1A)
    static let quidFailureText = quidDynamic(light: 0x9A2B1F, dark: 0xF3A89D)
}

extension UIColor {
    convenience init(quidHex hex: UInt32) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }
}

/// Background/foreground pair for initials avatars. Picked deterministically from the name.
struct AvatarTint: Hashable {
    let background: Color
    let foreground: Color

    static let all: [AvatarTint] = [
        AvatarTint(background: .quidDynamic(light: 0xDCEBE3, dark: 0x1F4A3C), foreground: .quidDynamic(light: 0x0B6B54, dark: 0xA3E4C8)),
        AvatarTint(background: .quidDynamic(light: 0xF3E7D3, dark: 0x4A3719), foreground: .quidDynamic(light: 0x7A4E10, dark: 0xF3C27B)),
        AvatarTint(background: .quidDynamic(light: 0xDDE8F3, dark: 0x1E3A52), foreground: .quidDynamic(light: 0x1F4E79, dark: 0xA9CDEE)),
        AvatarTint(background: .quidDynamic(light: 0xE6E1F2, dark: 0x332A52), foreground: .quidDynamic(light: 0x4B3A82, dark: 0xC9BDF0)),
        AvatarTint(background: .quidDynamic(light: 0xF5E1E4, dark: 0x4F2630), foreground: .quidDynamic(light: 0x8A2F45, dark: 0xF2B4C2)),
        AvatarTint(background: .quidDynamic(light: 0xD9F0EA, dark: 0x16433A), foreground: .quidDynamic(light: 0x0B5A4A, dark: 0x9FE0CF)),
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
