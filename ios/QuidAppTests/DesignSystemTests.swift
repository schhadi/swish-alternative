import UIKit
import XCTest
@testable import QuidApp

final class DesignSystemTests: XCTestCase {
    func testInitials() {
        XCTAssertEqual(Avatar.initials(for: "Priya Patel"), "PP")
        XCTAssertEqual(Avatar.initials(for: "cher"), "C")
        XCTAssertEqual(Avatar.initials(for: "SOAS Hockey Club"), "SH")
        XCTAssertEqual(Avatar.initials(for: "   "), "?")
        XCTAssertEqual(Avatar.initials(for: ""), "?")
    }

    func testAvatarTintIsStable() {
        XCTAssertEqual(AvatarTint.tint(for: "Priya Patel"), AvatarTint.tint(for: "Priya Patel"))
    }

    func testPaymentStatusMapsToThreeWords() {
        XCTAssertEqual(PaymentStatus.settled.pillText, "Paid")
        XCTAssertEqual(PaymentStatus.executed.pillText, "Paid")
        XCTAssertEqual(PaymentStatus.authorizing.pillText, "Pending")
        XCTAssertEqual(PaymentStatus.created.pillText, "Pending")
        XCTAssertEqual(PaymentStatus.failed.pillText, "Failed")
        XCTAssertEqual(PaymentStatus.cancelled.pillText, "Cancelled")
        XCTAssertEqual(PaymentStatus.settled.pillTone, .success)
        XCTAssertEqual(PaymentStatus.authorized.pillTone, .pending)
        XCTAssertEqual(PaymentStatus.failed.pillTone, .failure)
    }

    func testFinalStates() {
        XCTAssertTrue(PaymentStatus.settled.isFinal)
        XCTAssertTrue(PaymentStatus.failed.isFinal)
        XCTAssertFalse(PaymentStatus.executed.isFinal)
        XCTAssertFalse(PaymentStatus.authorizing.isFinal)
    }

    func testPhoneFormatting() {
        XCTAssertEqual(MeViewModel.formattedPhone("+447700900001"), "+44 7700 900001")
        XCTAssertEqual(MeViewModel.formattedPhone("+15551234567"), "+15551234567")
        XCTAssertEqual(MeViewModel.formattedPhone(nil), "")
    }

    // MARK: Contrast (SPEC 8: 4.5:1), light and dark

    /// Every text colour the screens draw, on every fill it is drawn on.
    private let textPairs: [(name: String, text: UIColor, fill: UIColor)] = [
        ("ink on background", QuidPalette.ink, QuidPalette.background),
        ("ink on surface", QuidPalette.ink, QuidPalette.surface),
        ("ink on secondary", QuidPalette.ink, QuidPalette.surfaceSecondary),
        ("ink on secondary pressed", QuidPalette.ink, QuidPalette.surfaceSecondaryPressed),
        ("muted on background", QuidPalette.muted, QuidPalette.background),
        ("muted on surface", QuidPalette.muted, QuidPalette.surface),
        ("muted on secondary", QuidPalette.muted, QuidPalette.surfaceSecondary),
        ("accent text on background", QuidPalette.accentText, QuidPalette.background),
        ("accent text on surface", QuidPalette.accentText, QuidPalette.surface),
        ("accent text on secondary", QuidPalette.accentText, QuidPalette.surfaceSecondary),
        ("on-accent on accent", QuidPalette.onAccent, QuidPalette.accent),
        ("on-accent on accent pressed", QuidPalette.onAccent, QuidPalette.accentPressed),
        ("success text on success tint", QuidPalette.successText, QuidPalette.successTint),
        ("pending text on pending tint", QuidPalette.pendingText, QuidPalette.pendingTint),
        ("failure text on failure tint", QuidPalette.failureText, QuidPalette.failureTint),
        ("success text on surface", QuidPalette.successText, QuidPalette.surface),
        ("pending text on surface", QuidPalette.pendingText, QuidPalette.surface),
        ("failure text on surface", QuidPalette.failureText, QuidPalette.surface),
        ("ink on success tint", QuidPalette.ink, QuidPalette.successTint),
        ("ink on pending tint", QuidPalette.ink, QuidPalette.pendingTint),
        ("ink on failure tint", QuidPalette.ink, QuidPalette.failureTint),
        ("muted on pending tint", QuidPalette.muted, QuidPalette.pendingTint),
        ("muted on failure tint", QuidPalette.muted, QuidPalette.failureTint),
    ]

    func testEveryTextPairMeetsContrastInBothAppearances() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            for pair in textPairs {
                let ratio = Self.contrast(pair.text, pair.fill, style: style)
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(pair.name) in \(style == .dark ? "dark" : "light") is \(String(format: "%.2f", ratio)):1")
            }
            for (index, tint) in AvatarTint.all.enumerated() {
                let ratio = Self.contrast(tint.foregroundColor, tint.backgroundColor, style: style)
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "avatar tint \(index) is \(String(format: "%.2f", ratio)):1")
            }
        }
    }

    func testDarkModeInvertsSurfacesAndKeepsTheAccent() {
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        XCTAssertLessThan(Self.luminance(QuidPalette.background, traits: dark), Self.luminance(QuidPalette.background, traits: light))
        XCTAssertGreaterThan(Self.luminance(QuidPalette.ink, traits: dark), Self.luminance(QuidPalette.ink, traits: light))
        XCTAssertEqual(Self.luminance(QuidPalette.accent, traits: dark), Self.luminance(QuidPalette.accent, traits: light), accuracy: 0.0001)
    }

    func testContrastFormulaMatchesKnownValues() {
        XCTAssertEqual(Self.contrast(.black, .white, style: .light), 21, accuracy: 0.01)
        XCTAssertEqual(Self.contrast(.white, .white, style: .light), 1, accuracy: 0.01)
    }

    /// WCAG 2 relative luminance of the colour as resolved for the given traits.
    private static func luminance(_ color: UIColor, traits: UITraitCollection) -> Double {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func linear(_ channel: CGFloat) -> Double {
            let value = Double(channel)
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    private static func contrast(_ first: UIColor, _ second: UIColor, style: UIUserInterfaceStyle) -> Double {
        let traits = UITraitCollection(userInterfaceStyle: style)
        let a = luminance(first, traits: traits)
        let b = luminance(second, traits: traits)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}
