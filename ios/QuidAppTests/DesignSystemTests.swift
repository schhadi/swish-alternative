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
}
