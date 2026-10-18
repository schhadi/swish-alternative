import XCTest
@testable import QuidApp

final class DateFormattingTests: XCTestCase {
    func testSectionTitles() {
        let calendar = Calendar.current
        XCTAssertEqual(Date().quidSectionTitle, "Today")
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        XCTAssertEqual(yesterday.quidSectionTitle, "Yesterday")
        let lastMonth = calendar.date(byAdding: .day, value: -40, to: Date())!
        XCTAssertNotEqual(lastMonth.quidSectionTitle, "Today")
        XCTAssertFalse(lastMonth.quidSectionTitle.isEmpty)
    }

    func testRelativeDescriptions() {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        XCTAssertEqual(yesterday.quidRelativeDescription, "Yesterday")
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: Date())!
        XCTAssertEqual(threeDaysAgo.quidRelativeDescription, threeDaysAgo.formatted(.dateTime.weekday(.wide)))
        let longAgo = calendar.date(byAdding: .day, value: -400, to: Date())!
        XCTAssertTrue(longAgo.quidRelativeDescription.contains(String(calendar.component(.year, from: longAgo))))
    }

    func testDueDescriptions() {
        XCTAssertEqual(Date().quidDueDescription, "Due today")
        XCTAssertEqual(Date().addingTimeInterval(-86_400 * 2).quidDueDescription, "Overdue")
        XCTAssertTrue(Date().addingTimeInterval(86_400 * 5).quidDueDescription.hasPrefix("Due "))
    }

    func testISO8601RoundTripsWithFractionalSeconds() {
        let date = Date(timeIntervalSince1970: 1_700_000_000.5)
        let string = ISO8601.string(from: date)
        XCTAssertEqual(ISO8601.date(from: string)?.timeIntervalSince1970 ?? 0, date.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertNotNil(ISO8601.date(from: "2026-10-18T14:05:00Z"))
        XCTAssertNotNil(ISO8601.date(from: "2026-10-18T14:05:00.000Z"))
        XCTAssertNil(ISO8601.date(from: "18/10/2026"))
    }
}
