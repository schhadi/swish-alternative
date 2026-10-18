import XCTest
@testable import QuidApp

@MainActor
final class OnboardingTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "OnboardingTests")!
        defaults.removePersistentDomain(forName: "OnboardingTests")
    }

    override func tearDown() {
        MockServer.shared.reset()
        super.tearDown()
    }

    private func freshEnvironment(signedIn: Bool) -> AppEnvironment {
        let environment = AppEnvironment.demo(signedIn: signedIn, defaults: defaults)
        MockServer.shared.latency = 0
        return environment
    }

    func testNewUserWalksEveryStep() async throws {
        let environment = freshEnvironment(signedIn: false)
        XCTAssertFalse(environment.session.isSignedIn)
        let viewModel = OnboardingViewModel(environment: environment)
        XCTAssertEqual(viewModel.rootStep, .phone)
        XCTAssertTrue(viewModel.canCancel)

        viewModel.phoneInput = "07700900001"
        XCTAssertEqual(viewModel.phoneInput, "07700 900001")
        XCTAssertTrue(viewModel.phoneIsValid)
        await viewModel.submitPhone()
        XCTAssertNil(viewModel.error)
        XCTAssertEqual(viewModel.path, [.code])
        XCTAssertEqual(viewModel.phoneE164, "+447700900001")
        XCTAssertEqual(viewModel.maskedPhone, "+44 7700 ***001")
        XCTAssertFalse(viewModel.canResend)

        viewModel.code = "12-34-56"
        XCTAssertEqual(viewModel.code, "123456")
        await viewModel.submitCode()
        XCTAssertNil(viewModel.error)
        XCTAssertTrue(environment.session.isSignedIn)
        XCTAssertEqual(viewModel.path.last, .name)
        XCTAssertFalse(viewModel.canCancel)

        viewModel.displayName = "  Sam Okafor "
        XCTAssertTrue(viewModel.nameIsValid)
        await viewModel.submitName()
        XCTAssertEqual(viewModel.path.last, .bank)
        XCTAssertEqual(environment.profile?.user.displayName, "Sam Okafor")

        let bank = viewModel.bankLink
        await bank.loadProviders()
        XCTAssertFalse(bank.providers.isEmpty)
        bank.selectedProvider = bank.providers.first { $0.id == "ob-starling" }
        bank.sortCode = "12-34-56"
        XCTAssertEqual(bank.sortCode, "123456")
        XCTAssertEqual(bank.formattedSortCode, "12-34-56")
        bank.accountNumber = "1234 5678 9"
        XCTAssertEqual(bank.accountNumber, "12345678")
        bank.accountHolderName = "Sam Okafor"
        XCTAssertTrue(bank.isValid)
        await viewModel.submitBank()
        XCTAssertEqual(viewModel.path.last, .copResult)
        XCTAssertEqual(bank.result?.copStatus, .match)
        XCTAssertEqual(bank.result?.bankAccount?.bankName, "Starling")

        await viewModel.continueAfterBank()
        XCTAssertEqual(viewModel.path.last, .contacts)
        XCTAssertEqual(environment.profile?.bankAccount?.bankName, "Starling")

        await viewModel.finish()
        XCTAssertTrue(environment.contactsExplainerSeen)
        XCTAssertFalse(environment.onboardingInProgress)
        XCTAssertNil(environment.pendingOnboardingStep)
    }

    func testWrongCodesCountDownAndLock() async {
        let environment = freshEnvironment(signedIn: false)
        let viewModel = OnboardingViewModel(environment: environment)
        viewModel.phoneInput = "07700 900001"
        await viewModel.submitPhone()
        for expectedRemaining in stride(from: 4, through: 1, by: -1) {
            viewModel.code = "000000"
            await viewModel.submitCode()
            XCTAssertEqual(viewModel.error?.code, "otp_invalid")
            XCTAssertEqual(viewModel.attemptsRemaining, expectedRemaining)
            XCTAssertEqual(viewModel.code, "")
            XCTAssertFalse(viewModel.isLocked)
        }
        viewModel.code = "000000"
        await viewModel.submitCode()
        XCTAssertTrue(viewModel.isLocked)
        XCTAssertEqual(viewModel.error?.code, "otp_locked")
        XCTAssertFalse(environment.session.isSignedIn)
        // A new code resets the lock.
        await viewModel.submitPhone()
        XCTAssertFalse(viewModel.isLocked)
        viewModel.code = MockMode.otpCode
        await viewModel.submitCode()
        XCTAssertTrue(environment.session.isSignedIn)
    }

    func testInvalidPhoneIsRejectedBeforeAnyRequest() async {
        let environment = freshEnvironment(signedIn: false)
        let viewModel = OnboardingViewModel(environment: environment)
        viewModel.phoneInput = "+1 555 123 4567"
        XCTAssertFalse(viewModel.phoneIsValid)
        await viewModel.submitPhone()
        XCTAssertTrue(viewModel.path.isEmpty)
        XCTAssertTrue(MockServer.shared.recordedRequests().isEmpty)
    }

    func testCloseMatchOffersTheBanksName() async {
        let environment = freshEnvironment(signedIn: false)
        let bank = BankLinkViewModel(api: environment.api)
        bank.sortCode = "123456"
        bank.accountNumber = "12345678"
        bank.accountHolderName = "sam okafor"
        await bank.submit()
        XCTAssertEqual(bank.result?.copStatus, .closeMatch)
        XCTAssertEqual(bank.result?.suggestedAccountHolderName, "Sam Okafor")
        XCTAssertNil(bank.result?.bankAccount)
        await bank.acceptSuggestedName()
        XCTAssertEqual(bank.accountHolderName, "Sam Okafor")
        XCTAssertEqual(bank.result?.copStatus, .match)
    }

    func testNoMatchStoresNothingAndCanBeSkipped() async {
        let environment = freshEnvironment(signedIn: false)
        let viewModel = OnboardingViewModel(environment: environment)
        viewModel.phoneInput = "07700 900001"
        await viewModel.submitPhone()
        viewModel.code = MockMode.otpCode
        await viewModel.submitCode()
        viewModel.displayName = "Sam Okafor"
        await viewModel.submitName()
        let bank = viewModel.bankLink
        bank.sortCode = "999999"
        bank.accountNumber = "12345678"
        bank.accountHolderName = "Sam Okafor"
        await viewModel.submitBank()
        XCTAssertEqual(bank.result?.copStatus, .noMatch)
        XCTAssertEqual(viewModel.path.last, .copResult)
        viewModel.editBankDetails()
        XCTAssertEqual(viewModel.path.last, .bank)
        XCTAssertNil(bank.result)
        viewModel.skipBank()
        XCTAssertTrue(environment.bankLinkSkipped)
        XCTAssertEqual(viewModel.path.last, .contacts)
        await viewModel.finish()
        XCTAssertNil(environment.pendingOnboardingStep)
        XCTAssertNil(environment.profile?.bankAccount)
    }

    func testResumesAtTheOutstandingStep() async {
        let environment = freshEnvironment(signedIn: true)
        MockFixtures.state.displayName = ""
        await environment.loadProfile()
        XCTAssertEqual(environment.pendingOnboardingStep, .name)
        XCTAssertEqual(OnboardingViewModel(environment: environment).rootStep, .name)

        MockFixtures.state.displayName = "Sam Okafor"
        MockFixtures.state.bankLinked = false
        await environment.loadProfile()
        XCTAssertEqual(environment.pendingOnboardingStep, .bank)

        environment.markBankLinkSkipped()
        XCTAssertEqual(environment.pendingOnboardingStep, .contacts)
        environment.markContactsExplainerSeen()
        XCTAssertNil(environment.pendingOnboardingStep)

        MockFixtures.state.bankLinked = true
        await environment.loadProfile()
        XCTAssertNil(environment.pendingOnboardingStep)
    }

    func testSignOutClearsSessionAndFlags() async {
        let environment = freshEnvironment(signedIn: true)
        await environment.loadProfile()
        environment.markContactsExplainerSeen()
        await environment.signOut()
        XCTAssertFalse(environment.session.isSignedIn)
        XCTAssertNil(environment.profile)
        XCTAssertFalse(environment.contactsExplainerSeen)
        XCTAssertEqual(MockServer.shared.recordedRequests().last?.url?.path(percentEncoded: false), "/auth/logout")
    }

    func testExpiredSessionSignsOut() async {
        let environment = freshEnvironment(signedIn: true)
        MockServer.shared.register(.get, "/me", .json(#"{"error":"unauthorized","message":"Session expired"}"#, status: 401))
        await environment.loadProfile()
        XCTAssertFalse(environment.session.isSignedIn)
        XCTAssertEqual(environment.profileError, .unauthorized)
    }
}
