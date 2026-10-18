import XCTest

/// Smoke test: the app launches in MockMode and the four tabs are there. The pay-flow XCUITest lands in Phase 5.
final class QuidAppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTabBarShowsInMockMode() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-mock"]
        app.launch()

        let home = app.tabBars.buttons["Home"]
        XCTAssertTrue(home.waitForExistence(timeout: 20))
        XCTAssertTrue(app.tabBars.buttons["Activity"].exists)
        XCTAssertTrue(app.tabBars.buttons["Collect"].exists)
        XCTAssertTrue(app.tabBars.buttons["Me"].exists)

        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 10))
    }
}
