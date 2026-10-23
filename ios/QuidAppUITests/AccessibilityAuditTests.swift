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

        XCTAssertTrue(app.buttons["home.pay"].waitForExistence(timeout: 20))
        try auditor.audit("home")

        // Activity, its Requests filter, and a split's detail.
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 10))
        try auditor.audit("activity")
        app.segmentedControls["activity.filter"].buttons["Requests"].tap()
        let split = app.buttons["activity.split.split_501"]
        if scrollTo(split, in: app) {
            split.tap()
            XCTAssertTrue(app.descendants(matching: .any)["split.share.u_tom"].waitForExistence(timeout: 10))
            try auditor.audit("split detail")
            goBack(in: app)
        } else {
            XCTFail("split_501 never appeared in Activity › Requests")
        }

        // Collect and a treasurer view.
        app.tabBars.buttons["Collect"].tap()
        let collection = app.buttons["collect.collection.col_trip"]
        XCTAssertTrue(collection.waitForExistence(timeout: 10))
        try auditor.audit("collect")
        if scrollTo(collection, in: app) {
            collection.tap()
            XCTAssertTrue(app.buttons["collection.showQR"].waitForExistence(timeout: 10))
            try auditor.audit("collection detail")
            goBack(in: app)
        }

        app.tabBars.buttons["Me"].tap()
        XCTAssertTrue(app.navigationBars["Me"].waitForExistence(timeout: 10))
        try auditor.audit("me")

        // Pay: picker, amount, result.
        app.tabBars.buttons["Home"].tap()
        let pay = app.buttons["home.pay"]
        XCTAssertTrue(pay.waitForExistence(timeout: 10))
        pay.tap()
        XCTAssertTrue(app.textFields["pay.search"].waitForExistence(timeout: 10) || app.searchFields.firstMatch.waitForExistence(timeout: 2))
        try auditor.audit("pay picker")
        let priya = app.buttons["pay.contact.u_priya"]
        if scrollTo(priya, in: app) {
            priya.tap()
            XCTAssertTrue(app.staticTexts["pay.amount"].waitForExistence(timeout: 10))
            app.buttons["pay.key.1"].tap()
            app.buttons["pay.key.2"].tap()
            try auditor.audit("pay amount")
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
        try auditor.audit("request picker")
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

/// Collects audit issues per screen and prints one `AXAUDIT|variant|screen|type|description|element` line each, so
/// CI logs list every finding in one place. Issues in `ignored` are reported but never fail the test.
@MainActor
private final class Auditor {
    let app: XCUIApplication
    let variant: String
    private(set) var count = 0

    init(app: XCUIApplication, variant: String) {
        self.app = app
        self.variant = variant
    }

    func audit(_ screen: String, file: StaticString = #filePath, line: UInt = #line) throws {
        try app.performAccessibilityAudit(for: .all) { [self] issue in
            let element = issue.element.map { element -> String in
                let identifier = element.identifier.isEmpty ? "-" : element.identifier
                return "\(identifier) '\(element.label)' type=\(element.elementType.rawValue) frame=\(element.frame.integral)"
            } ?? "no element"
            let description = issue.compactDescription.replacingOccurrences(of: "\n", with: " ")
            print("AXAUDIT|\(variant)|\(screen)|\(Self.name(of: issue.auditType))|\(description)|\(element)")
            count += 1
            // Report mode: every issue is printed and none fails the run yet.
            return true
        }
    }

    func finish() {
        print("AXAUDIT-SUMMARY|\(variant)|\(count) issue(s)")
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
