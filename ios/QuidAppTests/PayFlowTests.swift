import XCTest
@testable import QuidApp

@MainActor
final class PayFlowTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "PayFlowTests")!
        defaults.removePersistentDomain(forName: "PayFlowTests")
    }

    override func tearDown() {
        MockServer.shared.reset()
        super.tearDown()
    }

    private func environment() async -> AppEnvironment {
        let environment = AppEnvironment.demo(signedIn: true, defaults: defaults)
        MockServer.shared.latency = 0
        await environment.loadProfile()
        return environment
    }

    private func viewModel(target: PayTarget?, authoriser: MockPaymentAuthoriser? = nil) async -> (PayViewModel, MockPaymentAuthoriser) {
        // Built here rather than as a default argument: default arguments are evaluated outside the main actor.
        let authoriser = authoriser ?? MockPaymentAuthoriser()
        let viewModel = PayViewModel(environment: await environment(), target: target, authoriser: authoriser)
        authoriser.delay = 0
        viewModel.pollInterval = .milliseconds(20)
        viewModel.pollTimeout = .seconds(10)
        return (viewModel, authoriser)
    }

    private let priya = PayTarget(userId: "u_priya", displayName: "Priya Patel", bankName: "Starling")
    private let amara = PayTarget(userId: "u_amara", displayName: "Amara Osei", bankName: "Lloyds")

    func testKeypadBuildsAnAmountWithAtMostTwoDecimals() async {
        let (viewModel, _) = await viewModel(target: priya)
        XCTAssertEqual(viewModel.amountDisplay, "£0")
        XCTAssertEqual(viewModel.amountMinor, 0)
        viewModel.press(.digit(1))
        viewModel.press(.digit(2))
        viewModel.press(.point)
        viewModel.press(.point)
        viewModel.press(.digit(5))
        viewModel.press(.digit(0))
        viewModel.press(.digit(9))
        XCTAssertEqual(viewModel.amountText, "12.50")
        XCTAssertEqual(viewModel.amountMinor, 1250)
        viewModel.press(.delete)
        viewModel.press(.delete)
        XCTAssertEqual(viewModel.amountText, "12.")
        XCTAssertEqual(viewModel.amountMinor, 1200)
        viewModel.press(.delete)
        for _ in 0..<6 { viewModel.press(.digit(9)) }
        XCTAssertEqual(viewModel.amountText, "12999", "five pounds digits at most")
        viewModel.setQuickAmount(2000)
        XCTAssertEqual(viewModel.amountText, "20")
        XCTAssertEqual(viewModel.amountMinor, 2000)
        XCTAssertEqual(PayViewModel.minor(from: "0.5"), 50)
        XCTAssertEqual(PayViewModel.text(fromMinor: 1205), "12.05")
    }

    func testReferenceDefaultsToFromFirstNameAndStaysFasterPaymentsSafe() async {
        let (viewModel, _) = await viewModel(target: priya)
        XCTAssertEqual(viewModel.reference, "From Sam")
        viewModel.reference = "Dinner £ at Nando's on 12/10 — thanks!!"
        XCTAssertEqual(viewModel.reference, "Dinner  at Nandos ")
        XCTAssertEqual(viewModel.reference.count, 18)
        XCTAssertEqual(viewModel.referenceRemaining, 0)
        viewModel.reference = "   "
        XCTAssertFalse(viewModel.referenceIsValid)
    }

    func testPayIsOnlyPossibleWithinTheLimitAndWithAReceivingPayee() async {
        let (viewModel, _) = await viewModel(target: priya)
        XCTAssertFalse(viewModel.canPay)
        viewModel.setQuickAmount(1000)
        XCTAssertTrue(viewModel.canPay)
        XCTAssertEqual(viewModel.payButtonTitle, "Pay £10 with Monzo")
        viewModel.setQuickAmount(25001)
        XCTAssertFalse(viewModel.canPay)
        XCTAssertEqual(viewModel.inlineMessage, "The most you can send in one payment is £250.")

        let jonas = PayTarget(userId: "u_jonas", displayName: "Jonas Berg", bankName: nil, canReceive: false)
        let (blocked, _) = await self.viewModel(target: jonas)
        blocked.setQuickAmount(500)
        XCTAssertFalse(blocked.canPay)
        XCTAssertEqual(blocked.inlineMessage, "Jonas hasn't linked a verified bank account yet, so they can't be paid.")
    }

    func testKnownPayeeGoesStraightToTheBankAndEndsPaid() async throws {
        let (viewModel, authoriser) = await viewModel(target: priya)
        viewModel.setQuickAmount(1200)
        await viewModel.submit()
        XCTAssertNil(viewModel.error)
        XCTAssertNil(viewModel.pendingFirstTime, "Priya has been paid before")
        XCTAssertEqual(authoriser.requests.count, 1)
        XCTAssertEqual(authoriser.requests.first?.returnURL, AppConfig.paymentReturnURL)
        XCTAssertEqual(viewModel.path, [.result])
        XCTAssertEqual(viewModel.resultKind, .pending)
        XCTAssertEqual(viewModel.payment?.status, .authorizing)

        // The mock backend turns the payment EXECUTED after 2 s; polling picks that up.
        let deadline = Date().addingTimeInterval(6)
        while viewModel.resultKind != .paid, Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(viewModel.resultKind, .paid)
        XCTAssertEqual(viewModel.payment?.amountMinor, 1200)
        viewModel.done()
        XCTAssertTrue(viewModel.finished)
    }

    func testFirstTimePayeeShowsTheWarningBeforeTheBank() async {
        let (viewModel, authoriser) = await viewModel(target: amara)
        viewModel.setQuickAmount(500)
        await viewModel.submit()
        XCTAssertNotNil(viewModel.pendingFirstTime)
        XCTAssertEqual(viewModel.pendingFirstTime?.payee.accountHolderName, "Amara Osei")
        XCTAssertEqual(viewModel.pendingFirstTime?.payee.bankName, "Lloyds")
        XCTAssertTrue(authoriser.requests.isEmpty)
        XCTAssertTrue(viewModel.path.isEmpty)

        viewModel.cancelFirstTime()
        XCTAssertNil(viewModel.pendingFirstTime)
        XCTAssertNil(viewModel.created)

        await viewModel.submit()
        await viewModel.confirmFirstTime()
        XCTAssertEqual(authoriser.requests.count, 1)
        XCTAssertEqual(viewModel.path, [.result])
        viewModel.stopPolling()
    }

    func testCancellingInTheBankShowsFailedWithTryAgain() async {
        let authoriser = MockPaymentAuthoriser()
        authoriser.outcome = .cancelled
        let (viewModel, _) = await viewModel(target: priya, authoriser: authoriser)
        viewModel.setQuickAmount(500)
        await viewModel.submit()
        XCTAssertEqual(viewModel.path, [.result])
        XCTAssertEqual(viewModel.resultKind, .failed("You cancelled the payment in your bank app. Nothing has been sent."))
        viewModel.tryAgain()
        XCTAssertTrue(viewModel.path.isEmpty)
        XCTAssertNil(viewModel.created)
        XCTAssertEqual(viewModel.amountMinor, 500, "the amount is kept")
    }

    func testServerErrorsShowInline() async {
        let (viewModel, authoriser) = await viewModel(target: priya)
        MockServer.shared.register(.post, "/payments", .json(#"{"error":"limit_24h","message":"You can send £40 more in the next 24 hours.","details":{"limitMinor":50000,"remainingMinor":4000}}"#, status: 400))
        viewModel.setQuickAmount(5000)
        await viewModel.submit()
        XCTAssertEqual(viewModel.error?.code, "limit_24h")
        XCTAssertEqual(viewModel.inlineMessage, "You can send £40 more in the next 24 hours.")
        XCTAssertTrue(authoriser.requests.isEmpty)
        XCTAssertTrue(viewModel.path.isEmpty)
    }

    func testPollingGivesUpAfterTheWindowAndLeavesThePaymentPending() async throws {
        let (viewModel, _) = await viewModel(target: priya)
        viewModel.pollTimeout = .milliseconds(80)
        MockServer.shared.register(.get, "/payments/p_m1", .json(MockFixtures.createdPaymentJSON(MockCreatedPayment(id: "p_m1", payeeUserId: "u_priya", payeeName: "Priya Patel", amountMinor: 500, reference: "From Sam", createdAt: Date().addingTimeInterval(600)))))
        viewModel.setQuickAmount(500)
        await viewModel.submit()
        let deadline = Date().addingTimeInterval(3)
        while !viewModel.pollingTimedOut, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(viewModel.pollingTimedOut)
        XCTAssertEqual(viewModel.resultKind, .pending)
    }

    func testContactPickerSplitsRegisteredAndInvitable() async {
        let environment = await environment()
        let picker = ContactPickerViewModel(contactSource: environment.contactSource, api: environment.api)
        XCTAssertEqual(picker.permission, .granted)
        await picker.load()
        XCTAssertEqual(picker.registered.map(\.contact.displayName), ["Amara Osei", "Jonas Berg", "Priya Patel", "Tom Whitfield"])
        XCTAssertEqual(picker.others.map(\.contact.displayName), ["Ben Carter", "Nadia Hussain"])
        let jonas = picker.registered.first { $0.contact.displayName == "Jonas Berg" }
        XCTAssertEqual(jonas?.registered?.canReceive, false)
        XCTAssertNil(jonas?.registered?.bankName)
        let priya = picker.registered.first { $0.contact.displayName == "Priya Patel" }
        XCTAssertEqual(priya?.registered?.bankName, "Starling")
        XCTAssertEqual(priya.map { PayTarget(registered: $0.registered!) }?.canReceive, true)

        picker.searchText = "pri"
        XCTAssertEqual(picker.registered.map(\.contact.displayName), ["Priya Patel"])
        XCTAssertTrue(picker.others.isEmpty)
        picker.searchText = "900010"
        XCTAssertEqual(picker.others.map(\.contact.displayName), ["Nadia Hussain"])
    }

    func testContactPickerAsksForPermissionFirst() async {
        let environment = await environment()
        let source = MockContactSource()
        source.authorizationStatus = .notDetermined
        let picker = ContactPickerViewModel(contactSource: source, api: environment.api)
        XCTAssertEqual(picker.permission, .undetermined)
        await picker.load()
        XCTAssertTrue(picker.entries.isEmpty)
        await picker.requestAccess()
        XCTAssertEqual(picker.permission, .granted)
        XCTAssertEqual(picker.entries.count, 6)

        let refusing = MockContactSource()
        refusing.authorizationStatus = .notDetermined
        refusing.accessGranted = false
        let denied = ContactPickerViewModel(contactSource: refusing, api: environment.api)
        await denied.requestAccess()
        XCTAssertEqual(denied.permission, .denied)
    }
}
