import XCTest

/// Launch and onboarding smoke tests against MockMode. The pay-flow XCUITest lands in Phase 5.
final class QuidAppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Waits for the element and, when it never appears, prints the whole hierarchy so CI logs show what was on screen.
    private func waitFor(_ element: XCUIElement, in app: XCUIApplication, timeout: TimeInterval = 20, file: StaticString = #filePath, line: UInt = #line) {
        if element.waitForExistence(timeout: timeout) { return }
        // state: 1 = not running (the app crashed or was killed), 4 = running in the foreground.
        print("UITEST-HIERARCHY-BEGIN\napp.state=\(app.state.rawValue)\n\(app.debugDescription)\nUITEST-HIERARCHY-END")
        XCTFail("\(element) did not appear within \(Int(timeout))s", file: file, line: line)
    }

    @MainActor
    func testTabBarShowsInMockMode() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-mock"]
        app.launch()

        let home = app.tabBars.buttons["Home"]
        waitFor(home, in: app, timeout: 20)
        XCTAssertTrue(app.tabBars.buttons["Activity"].exists)
        XCTAssertTrue(app.tabBars.buttons["Collect"].exists)
        XCTAssertTrue(app.tabBars.buttons["Me"].exists)

        app.tabBars.buttons["Activity"].tap()
        waitFor(app.navigationBars["Activity"], in: app, timeout: 10)
    }

    @MainActor
    func testOnboardingHappyPath() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-signed-out"]
        app.launch()

        let getStarted = app.buttons["welcome.getStarted"]
        waitFor(getStarted, in: app, timeout: 20)
        getStarted.tap()

        let phone = app.textFields["onboarding.phone"]
        waitFor(phone, in: app, timeout: 10)
        phone.tap()
        phone.typeText("07700900001")
        app.buttons["onboarding.sendCode"].tap()

        let code = app.textFields["onboarding.code"]
        waitFor(code, in: app, timeout: 10)
        // The field is focused on appear and sits under the six boxes, so type without tapping it.
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
        code.typeText("123456")

        let name = app.textFields["onboarding.name"]
        waitFor(name, in: app, timeout: 10)
        name.tap()
        name.typeText("Sam Okafor")
        app.buttons["onboarding.nameContinue"].tap()

        let sortCode = app.textFields["bank.sortCode"]
        waitFor(sortCode, in: app, timeout: 10)
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
        waitFor(copContinue, in: app, timeout: 10)
        copContinue.tap()

        let finish = app.buttons["onboarding.finish"]
        waitFor(finish, in: app, timeout: 10)
        finish.tap()

        waitFor(app.tabBars.buttons["Home"], in: app, timeout: 20)
    }
}
