import XCTest

/// Launch, onboarding, pay, request, pay-a-request and create-a-collection journeys against MockMode.
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

    /// Taps a field and waits until it has keyboard focus before returning. In a scrolling SwiftUI form the first tap
    /// can land while the keyboard-avoidance scroll is still settling, so it is retried.
    private func focus(_ field: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<3 {
            field.tap()
            let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: field)
            if XCTWaiter().wait(for: [focused], timeout: 2) == .completed { return }
        }
        XCTFail("\(field) never took keyboard focus", file: file, line: line)
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
    func testPayFlowFromRecentContact() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-mock"]
        app.launch()

        let priya = app.buttons["home.recent.u_priya"]
        waitFor(priya, in: app, timeout: 20)
        priya.tap()

        waitFor(app.staticTexts["pay.amount"], in: app, timeout: 10)
        app.buttons["pay.key.1"].tap()
        app.buttons["pay.key.2"].tap()
        XCTAssertEqual(app.staticTexts["pay.amount"].value as? String, "£12.00")
        let submit = app.buttons["pay.submit"]
        XCTAssertTrue(submit.isEnabled)
        submit.tap()

        // Priya has been paid before, so no first-time sheet; the mock bank approves and the result shows Pending then Paid.
        let title = app.staticTexts["pay.result.title"]
        waitFor(title, in: app, timeout: 15)
        let paid = NSPredicate(format: "label == %@", "Paid")
        let became = XCTNSPredicateExpectation(predicate: paid, object: title)
        XCTAssertEqual(XCTWaiter().wait(for: [became], timeout: 15), .completed, "result title was \(title.label)")
        app.buttons["pay.done"].tap()

        waitFor(app.tabBars.buttons["Home"], in: app, timeout: 10)
        XCTAssertTrue(app.staticTexts["Priya Patel"].firstMatch.waitForExistence(timeout: 10))
    }

    /// Waits until the element has gone, for things that disappear after a reload.
    private func waitForAbsence(_ element: XCUIElement, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        if XCTWaiter().wait(for: [gone], timeout: timeout) != .completed {
            XCTFail("\(element) was still there after \(Int(timeout))s", file: file, line: line)
        }
    }

    @MainActor
    func testRequestFlowCreatesASplit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-mock"]
        app.launch()

        let request = app.buttons["home.request"]
        waitFor(request, in: app, timeout: 20)
        request.tap()

        let priya = app.buttons["request.contact.u_priya"]
        waitFor(priya, in: app, timeout: 10)
        priya.tap()
        app.buttons["request.contact.u_tom"].tap()
        app.buttons["request.continue"].tap()

        let total = app.staticTexts["request.total"]
        waitFor(total, in: app, timeout: 10)
        app.buttons["pay.key.3"].tap()
        app.buttons["pay.key.0"].tap()
        XCTAssertEqual(total.value as? String, "£30.00")
        XCTAssertFalse(app.buttons["request.submit"].isEnabled, "a title is required")

        let title = app.textFields["request.title"]
        focus(title)
        title.typeText("Pizza")
        let submit = app.buttons["request.submit"]
        XCTAssertTrue(submit.isEnabled)
        submit.tap()

        // The new split's detail: sent banner and one row per person asked.
        waitFor(app.descendants(matching: .any)["split.sent"], in: app, timeout: 10)
        XCTAssertTrue(app.descendants(matching: .any)["split.share.u_priya"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["split.share.u_tom"].exists)
        app.buttons["split.done"].tap()
        waitFor(app.buttons["home.request"], in: app, timeout: 10)
    }

    @MainActor
    func testPayingARequestFromHome() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-mock"]
        app.launch()

        let pay = app.buttons["home.request.pay.req_301"]
        waitFor(pay, in: app, timeout: 20)
        pay.tap()

        let amount = app.staticTexts["pay.amount"]
        waitFor(amount, in: app, timeout: 10)
        XCTAssertEqual(amount.value as? String, "£18.00")
        XCTAssertFalse(app.buttons["pay.key.1"].exists, "a request fixes the amount")
        app.buttons["pay.submit"].tap()

        let resultTitle = app.staticTexts["pay.result.title"]
        waitFor(resultTitle, in: app, timeout: 15)
        let paid = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Paid"), object: resultTitle)
        XCTAssertEqual(XCTWaiter().wait(for: [paid], timeout: 15), .completed, "result title was \(resultTitle.label)")
        app.buttons["pay.done"].tap()

        waitFor(app.buttons["home.request"], in: app, timeout: 10)
        waitForAbsence(app.buttons["home.request.pay.req_301"])
        XCTAssertTrue(app.buttons["home.request.pay.req_302"].exists, "Tom's request is still open")
    }

    @MainActor
    func testCreatingACollectionAndShowingItsQRCode() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-mock"]
        app.launch()

        let collect = app.tabBars.buttons["Collect"]
        waitFor(collect, in: app, timeout: 20)
        collect.tap()
        let newCollection = app.buttons["collect.newCollection.org_hockey"]
        waitFor(newCollection, in: app, timeout: 10)
        newCollection.tap()

        let title = app.textFields["collection.title"]
        waitFor(title, in: app, timeout: 10)
        focus(title)
        title.typeText("Kit deposit")
        let amount = app.textFields["collection.amount"]
        focus(amount)
        amount.typeText("25")
        let name = app.textFields["collection.newName"]
        focus(name)
        name.typeText("Jamie Lee")
        app.buttons["collection.addName"].tap()

        let create = app.buttons["collection.create"]
        XCTAssertTrue(create.isEnabled)
        create.tap()

        // The new collection's treasurer view: created banner, Jamie on the list, the link's QR code.
        waitFor(app.descendants(matching: .any)["collection.created"], in: app, timeout: 10)
        XCTAssertTrue(app.descendants(matching: .any)["collection.member.cm1_1"].waitForExistence(timeout: 5))
        app.buttons["collection.showQR"].tap()
        waitFor(app.descendants(matching: .any)["collection.qr"], in: app, timeout: 10)
        app.buttons["collection.qr.done"].tap()
        waitFor(app.buttons["collection.showQR"], in: app, timeout: 10)
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
        focus(phone)
        phone.typeText("07700900001")
        app.buttons["onboarding.sendCode"].tap()

        let code = app.textFields["onboarding.code"]
        waitFor(code, in: app, timeout: 10)
        // The field is focused on appear and sits under the six boxes, so type without tapping it.
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
        code.typeText("123456")

        let name = app.textFields["onboarding.name"]
        waitFor(name, in: app, timeout: 10)
        focus(name)
        name.typeText("Sam Okafor")
        app.buttons["onboarding.nameContinue"].tap()

        let sortCode = app.textFields["bank.sortCode"]
        waitFor(sortCode, in: app, timeout: 10)
        focus(sortCode)
        sortCode.typeText("123456")
        let accountNumber = app.textFields["bank.accountNumber"]
        focus(accountNumber)
        accountNumber.typeText("12345678")
        let holder = app.textFields["bank.name"]
        focus(holder)
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
