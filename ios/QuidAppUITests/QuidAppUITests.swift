import XCTest

/// Launch and onboarding smoke tests against MockMode. The pay-flow XCUITest lands in Phase 5.
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

    @MainActor
    func testOnboardingHappyPath() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-signed-out"]
        app.launch()

        let getStarted = app.buttons["welcome.getStarted"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 20))
        getStarted.tap()

        let phone = app.textFields["onboarding.phone"]
        XCTAssertTrue(phone.waitForExistence(timeout: 10))
        phone.tap()
        phone.typeText("07700900001")
        app.buttons["onboarding.sendCode"].tap()

        let code = app.textFields["onboarding.code"]
        XCTAssertTrue(code.waitForExistence(timeout: 10))
        code.tap()
        code.typeText("123456")

        let name = app.textFields["onboarding.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        name.typeText("Sam Okafor")
        app.buttons["onboarding.nameContinue"].tap()

        let sortCode = app.textFields["bank.sortCode"]
        XCTAssertTrue(sortCode.waitForExistence(timeout: 10))
        sortCode.tap()
        sortCode.typeText("123456")
        let accountNumber = app.textFields["bank.accountNumber"]
        accountNumber.tap()
        accountNumber.typeText("12345678")
        let holder = app.textFields["bank.name"]
        holder.tap()
        holder.typeText("Sam Okafor")
        app.buttons["bank.verify"].tap()

        let copContinue = app.buttons["cop.continue"]
        XCTAssertTrue(copContinue.waitForExistence(timeout: 10))
        copContinue.tap()

        let finish = app.buttons["onboarding.finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 10))
        finish.tap()

        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 20))
    }
}
