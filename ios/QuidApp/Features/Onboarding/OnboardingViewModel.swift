import Foundation
import Observation

/// Drives phone -> code -> name -> bank -> CoP result -> contacts explainer, including resuming part-way.
@MainActor
@Observable
final class OnboardingViewModel {
    static let resendInterval: TimeInterval = 30

    let rootStep: OnboardingStep
    var path: [OnboardingStep] = []

    // Phone
    var phoneInput = "" {
        didSet {
            let formatted = UKPhone.formatNationalAsTyped(phoneInput)
            if formatted != phoneInput { phoneInput = formatted }
        }
    }
    private(set) var phoneE164: String?

    // Code
    var code = "" {
        didSet { code = String(code.filter(\.isNumber).prefix(6)) }
    }
    private(set) var attemptsRemaining: Int?
    private(set) var isLocked = false
    private(set) var resendAvailableAt: Date?

    // Name
    var displayName = ""

    // Bank
    let bankLink: BankLinkViewModel

    private(set) var isSubmitting = false
    private(set) var error: AppError?

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
        bankLink = BankLinkViewModel(api: environment.api)
        if environment.session.isSignedIn, let pending = environment.pendingOnboardingStep {
            rootStep = pending
        } else {
            rootStep = .phone
        }
        displayName = environment.profile?.user.displayName ?? ""
    }

    var currentStep: OnboardingStep {
        path.last ?? rootStep
    }

    var canCancel: Bool {
        !environment.session.isSignedIn
    }

    var phoneIsValid: Bool {
        UKPhone.normalise(phoneInput) != nil
    }

    var maskedPhone: String {
        phoneE164.map(UKPhone.masked) ?? ""
    }

    var nameIsValid: Bool {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 2 && trimmed.count <= 40
    }

    // MARK: - Phone

    func submitPhone() async {
        guard let e164 = UKPhone.normalise(phoneInput), !isSubmitting else { return }
        await perform {
            let response = try await environment.api.send(API.otpStart(phone: e164))
            phoneE164 = response.phoneE164
            code = ""
            attemptsRemaining = nil
            isLocked = false
            resendAvailableAt = Date().addingTimeInterval(OnboardingViewModel.resendInterval)
            if currentStep != .code {
                path.append(.code)
            }
        }
    }

    func resendCode() async {
        guard let resendAvailableAt, resendAvailableAt <= Date() else { return }
        await submitPhone()
    }

    var canResend: Bool {
        guard let resendAvailableAt else { return false }
        return resendAvailableAt <= Date()
    }

    func changeNumber() {
        code = ""
        error = nil
        isLocked = false
        if !path.isEmpty { path.removeLast() }
    }

    // MARK: - Code

    func submitCode() async {
        guard let phoneE164, code.count == 6, !isSubmitting, !isLocked else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let response = try await environment.api.send(API.otpVerify(phone: phoneE164, code: code))
            try environment.signIn(token: response.token)
            error = nil
            attemptsRemaining = nil
            await environment.loadProfile()
            if let next = environment.pendingOnboardingStep {
                displayName = environment.profile?.user.displayName ?? ""
                path.append(next)
            } else {
                await environment.finishOnboarding()
            }
        } catch is CancellationError {
            return
        } catch let appError as AppError {
            code = ""
            error = appError
            if case .api(let errorCode, _, let details) = appError {
                attemptsRemaining = details.attemptsRemaining
                isLocked = errorCode == "otp_locked"
            }
        } catch {
            code = ""
            self.error = .unknown(error.localizedDescription)
        }
    }

    // MARK: - Name

    func submitName() async {
        guard nameIsValid, !isSubmitting else { return }
        await perform {
            _ = try await environment.api.send(API.updateDisplayName(displayName.trimmingCharacters(in: .whitespacesAndNewlines)))
            await environment.loadProfile()
            path.append(environment.profile?.bankAccount == nil ? .bank : .contacts)
        }
    }

    // MARK: - Bank

    func submitBank() async {
        if await bankLink.submit() {
            path.append(.copResult)
        }
    }

    func acceptSuggestedBankName() async {
        _ = await bankLink.acceptSuggestedName()
    }

    func editBankDetails() {
        bankLink.editAgain()
        if path.last == .copResult { path.removeLast() }
    }

    func continueAfterBank() async {
        environment.bankAccountLinked()
        await environment.loadProfile()
        path.append(.contacts)
    }

    func skipBank() {
        environment.markBankLinkSkipped()
        path.append(.contacts)
    }

    // MARK: - Contacts

    func finish() async {
        environment.markContactsExplainerSeen()
        await environment.finishOnboarding()
    }

    func cancel() {
        environment.cancelOnboarding()
    }

    // MARK: - Helpers

    private func perform(_ work: () async throws -> Void) async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await work()
            error = nil
        } catch is CancellationError {
            return
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown(error.localizedDescription)
        }
    }
}
