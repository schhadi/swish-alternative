import XCTest

/// Runs Xcode's accessibility audit (contrast, hit regions, labels, Dynamic Type, clipped text, traits) over the main
/// screens in MockMode: light, dark, and the largest accessibility text size.
final class AccessibilityAuditTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor
    func testAuditLightAppearance() throws {
        try auditMainScreens(variant: "light", arguments: ["-light-mode"])
    }

    @MainActor
    func testAuditDarkAppearance() throws {
        try auditMainScreens(variant: "dark", arguments: ["-dark-mode"])
    }

    @MainActor
    func testAuditLargestTextSize() throws {
        try auditMainScreens(
            variant: "xxxl",
            arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        )
    }

    // MARK: Journey

    @MainActor
    private func auditMainScreens(variant: String, arguments: [String]) throws {
        let app = XCUIApplication()
        app.launchArguments = ["-mock"] + arguments
        app.launch()
        let auditor = Auditor(app: app, variant: variant)

        // Each screen is audited once its content has loaded, never on its loading placeholders.
        XCTAssertTrue(app.buttons["home.recent.u_priya"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["home.request.pay.req_301"].waitForExistence(timeout: 10))
        try auditor.audit("home")

        // Activity, its Requests filter, and a split's detail.
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Priya Patel"].firstMatch.waitForExistence(timeout: 10))
        try auditor.audit("activity")
        app.segmentedControls["activity.filter"].buttons["Requests"].tap()
        let split = app.buttons["activity.split.split_501"]
        if scrollTo(split, in: app) {
            split.tap()
            XCTAssertTrue(app.descendants(matching: .any)["split.share.u_tom"].waitForExistence(timeout: 10))
            try auditor.audit("split detail", bottomBar: app.buttons["split.remindAll"])
            goBack(in: app)
        } else {
            XCTFail("split_501 never appeared in Activity › Requests")
        }

        // Collect and a treasurer view.
        app.tabBars.buttons["Collect"].tap()
        let collection = app.buttons["collect.collection.col_trip"]
        XCTAssertTrue(collection.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["collect.due.col_climb"].waitForExistence(timeout: 10))
        try auditor.audit("collect")
        if scrollTo(collection, in: app) {
            collection.tap()
            XCTAssertTrue(app.buttons["collection.showQR"].waitForExistence(timeout: 10))
            try auditor.audit("collection detail", bottomBar: app.buttons["collection.remindAll"])
            goBack(in: app)
        }

        app.tabBars.buttons["Me"].tap()
        XCTAssertTrue(app.buttons["me.changeBank"].waitForExistence(timeout: 10))
        try auditor.audit("me")

        // Pay: picker, amount, result.
        app.tabBars.buttons["Home"].tap()
        let pay = app.buttons["home.pay"]
        XCTAssertTrue(pay.waitForExistence(timeout: 10))
        pay.tap()
        let priya = app.buttons["pay.contact.u_priya"]
        XCTAssertTrue(priya.waitForExistence(timeout: 10))
        try auditor.audit("pay picker")
        if scrollTo(priya, in: app) {
            priya.tap()
            XCTAssertTrue(app.staticTexts["pay.amount"].waitForExistence(timeout: 10))
            app.buttons["pay.key.1"].tap()
            app.buttons["pay.key.2"].tap()
            try auditor.audit("pay amount", bottomBar: app.buttons["pay.submit"])
            let submit = app.buttons["pay.submit"]
            if scrollTo(submit, in: app) {
                submit.tap()
                let title = app.staticTexts["pay.result.title"]
                XCTAssertTrue(title.waitForExistence(timeout: 15))
                let paid = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Paid"), object: title)
                _ = XCTWaiter().wait(for: [paid], timeout: 15)
                try auditor.audit("pay result")
                let done = app.buttons["pay.done"]
                if scrollTo(done, in: app) { done.tap() }
            }
        }

        // Request: the people picker.
        let request = app.buttons["home.request"]
        XCTAssertTrue(request.waitForExistence(timeout: 10))
        request.tap()
        XCTAssertTrue(app.buttons["request.contact.u_priya"].waitForExistence(timeout: 10))
        try auditor.audit("request picker", bottomBar: app.buttons["request.continue"])
        app.buttons["request.cancel"].tap()

        auditor.finish()
    }

    // MARK: Helpers

    /// Scrolls the frontmost scroll view until the element is hittable; false if it never is.
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, attempts: Int = 8) -> Bool {
        if !element.waitForExistence(timeout: 10) { return false }
        var tries = 0
        while !element.isHittable && tries < attempts {
            app.swipeUp()
            tries += 1
        }
        return element.isHittable
    }

    private func goBack(in app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.waitForExistence(timeout: 5) { back.tap() }
    }
}

/// Runs the audit on one screen and prints one `AXAUDIT|variant|screen|type|description|element|outcome` line per
/// finding, so CI lists them all in one place. Every finding fails the test except the kinds below, which are printed
/// with the reason they are not failures (docs/DECISIONS.md #97):
/// - anything drawn under the tab bar, a pinned bottom bar or the navigation bar: the audit measures it against the
///   bar's material and the scroll-edge effect, not against what a person sees once it is scrolled into view;
/// - disabled controls, which WCAG exempts from contrast;
/// - Dynamic Type on bar buttons: UIKit keeps bar items at bar size and offers the Large Content Viewer instead;
/// - text clipping, which the audit reports for single-line SwiftUI text that fits; rows wrap at accessibility sizes
///   (`quidLineLimit`), and the findings stay in the log for review;
/// - "potentially inaccessible text" with no element: avatar initials, hidden from VoiceOver on purpose because the row
///   reads the full name;
/// - Dynamic Type on avatar initials: the circle and its initials both grow with the text size (`Avatar`, ScaledMetric).
@MainActor
private final class Auditor {
    let app: XCUIApplication
    let variant: String
    private(set) var failures = 0
    private(set) var ignored = 0

    /// How far above a bar the scroll-edge effect reaches.
    private let barMargin: CGFloat = 60

    init(app: XCUIApplication, variant: String) {
        self.app = app
        self.variant = variant
    }

    func audit(_ screen: String, bottomBar: XCUIElement? = nil, file: StaticString = #filePath, line: UInt = #line) throws {
        let window = app.windows.firstMatch.frame
        var chromeTop = window.maxY
        let tabBar = app.tabBars.firstMatch
        if tabBar.exists, !tabBar.frame.isEmpty { chromeTop = min(chromeTop, tabBar.frame.minY) }
        if let bottomBar, bottomBar.exists, !bottomBar.frame.isEmpty { chromeTop = min(chromeTop, bottomBar.frame.minY) }
        let chromeLine = chromeTop - barMargin
        let navBar = app.navigationBars.firstMatch
        let navFrame = navBar.exists ? navBar.frame : .zero
        let navBottom = navBar.exists ? navFrame.maxY : window.minY

        do {
            try app.performAccessibilityAudit(for: .all) { [self] issue in
                handle(issue, screen: screen, chromeLine: chromeLine, navBottom: navBottom, navFrame: navFrame)
            }
        } catch {
            XCTFail("The accessibility audit of \(screen) could not run: \(error)", file: file, line: line)
        }
    }

    /// True when the finding is one of the documented exceptions; false fails the test.
    private func handle(_ issue: XCUIAccessibilityAuditIssue, screen: String, chromeLine: CGFloat, navBottom: CGFloat, navFrame: CGRect) -> Bool {
        let type = Self.name(of: issue.auditType)
        let element = issue.element
        let frame = element?.frame ?? .zero
        let inBarZone = element != nil && (frame.maxY > chromeLine || frame.minY < navBottom)
        let inNavBar = element != nil && navFrame.contains(CGPoint(x: frame.midX, y: frame.midY))

        let reason: String?
        switch type {
        case "textClipped":
            reason = "text clipping is reviewed, not enforced"
        case "elementDetection" where element == nil:
            reason = "decorative text hidden from VoiceOver"
        case "dynamicType" where inNavBar:
            reason = "bar button, Large Content Viewer"
        case "dynamicType" where Self.isAvatarInitials(element):
            reason = "avatar initials scale with their circle"
        case "contrast" where inBarZone:
            reason = "under a bar"
        case "contrast" where element?.isEnabled == false:
            reason = "disabled control"
        default:
            reason = nil
        }

        let described = element.map { element -> String in
            let identifier = element.identifier.isEmpty ? "-" : element.identifier
            return "\(identifier) '\(element.label)' type=\(element.elementType.rawValue) frame=\(element.frame.integral)"
        } ?? "no element"
        let description = issue.compactDescription.replacingOccurrences(of: "\n", with: " ")
        print("AXAUDIT|\(variant)|\(screen)|\(type)|\(description)|\(described)|\(reason.map { "ignored: \($0)" } ?? "FAIL")")
        if reason == nil {
            failures += 1
            return false
        }
        ignored += 1
        return true
    }

    /// One or two capital letters (or "?") in a square frame: the initials `Avatar` draws.
    private static func isAvatarInitials(_ element: XCUIElement?) -> Bool {
        guard let element else { return false }
        let frame = element.frame
        let square = frame.width > 0 && abs(frame.width - frame.height) <= 2
        return square && element.label.range(of: "^[A-Z?]{1,2}$", options: .regularExpression) != nil
    }

    func finish() {
        print("AXAUDIT-SUMMARY|\(variant)|\(failures) failing, \(ignored) ignored")
    }

    private static func name(of type: XCUIAccessibilityAuditType) -> String {
        let names: [(XCUIAccessibilityAuditType, String)] = [
            (.contrast, "contrast"),
            (.elementDetection, "elementDetection"),
            (.hitRegion, "hitRegion"),
            (.sufficientElementDescription, "sufficientElementDescription"),
            (.dynamicType, "dynamicType"),
            (.textClipped, "textClipped"),
            (.trait, "trait"),
        ]
        return names.first { type.contains($0.0) }?.1 ?? "type(\(type.rawValue))"
    }
}
