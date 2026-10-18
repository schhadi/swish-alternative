import XCTest
@testable import QuidApp

final class MoneyTests: XCTestCase {
    func testFormatsPoundsAndPence() {
        XCTAssertEqual(Money(minor: 1250).formatted(), "£12.50")
        XCTAssertEqual(Money(minor: 5).formatted(), "£0.05")
        XCTAssertEqual(Money(minor: 0).formatted(), "£0.00")
    }

    func testCompactDropsZeroPenceOnly() {
        XCTAssertEqual(Money(minor: 1200).formatted(compact: true), "£12")
        XCTAssertEqual(Money(minor: 1250).formatted(compact: true), "£12.50")
    }

    func testGroupsThousands() {
        XCTAssertEqual(Money(minor: 200_000).formatted(), "£2,000.00")
        XCTAssertEqual(Money(minor: 123_456_789).formatted(), "£1,234,567.89")
        XCTAssertEqual(Money.grouped(999), "999")
        XCTAssertEqual(Money.grouped(1000), "1,000")
    }

    func testNegativeUsesMinusSign() {
        XCTAssertEqual(Money(minor: -350).formatted(), "−£3.50")
    }

    func testExplicitPlusOnlyForPositive() {
        XCTAssertEqual(Money(minor: 600).formatted(explicitPlus: true), "+£6.00")
        XCTAssertEqual(Money(minor: 0).formatted(explicitPlus: true), "£0.00")
        XCTAssertEqual(Money(minor: -600).formatted(explicitPlus: true), "−£6.00")
    }

    func testPoundsFactory() {
        XCTAssertEqual(Money.pounds(30).minor, 3000)
    }
}
