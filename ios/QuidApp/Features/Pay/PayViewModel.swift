import Foundation
import Observation

/// One payment from choosing a person to the result screen (docs/SPEC.md section 8, screens 3 and 4).
@MainActor
@Observable
final class PayViewModel {
    enum Step: Hashable {
        case amount, result
    }

    enum KeypadKey: Hashable {
        case digit(Int), point, delete
    }

    static let quickAmountsMinor = [500, 1000, 2000, 5000]
    static let referenceMaxLength = 18
    static let fallbackPerPaymentLimitMinor = 25000

    /// Opened without a person: the contact picker is the root. Otherwise the amount screen is.
    let rootIsPicker: Bool
    var path: [Step] = []
    private(set) var target: PayTarget?

    // Amount screen
    /// As typed: "12", "12.", "12.5". Never more than two decimals or five pounds digits.
    private(set) var amountText = ""
    var reference = "" {
        didSet {
            let cleaned = PayViewModel.cleanReference(reference)
            if cleaned != reference { reference = cleaned }
        }
    }
    private(set) var isSubmitting = false
    private(set) var error: AppError?

    // After POST /payments
    private(set) var created: PaymentCreateResponseDTO?
    /// Set when the server flagged a first-time payee; the warning sheet is showing.
    private(set) var pendingFirstTime: PaymentCreateResponseDTO?
    /// The user tapped Pay on the sheet; authorisation starts once the sheet has gone (the SDK needs the screen).
    private(set) var confirmedFirstTime: PaymentCreateResponseDTO?
    private(set) var outcome: AuthorisationOutcome?
    private(set) var isAuthorising = false

    // Result screen
    private(set) var payment: PaymentDTO?
    private(set) var pollingTimedOut = false
    private(set) var finished = false
    var pollInterval: Duration = .seconds(3)
    var pollTimeout: Duration = .seconds(60)

    private let environment: AppEnvironment
    private let authoriser: any PaymentAuthoriser
    private var pollTask: Task<Void, Never>?

    init(environment: AppEnvironment, target: PayTarget?, authoriser: (any PaymentAuthoriser)? = nil) {
        self.environment = environment
        self.authoriser = authoriser ?? environment.paymentAuthoriser
        self.target = target
        rootIsPicker = target == nil
        reference = PayViewModel.defaultReference(for: environment.profile?.user.displayName)
    }

    // MARK: - Derived

    var profile: MeDTO? { environment.profile }

    var perPaymentLimitMinor: Int {
        profile?.limits.perPaymentMinor ?? PayViewModel.fallbackPerPaymentLimitMinor
    }

    var myBankName: String? {
        profile?.bankAccount?.bankName
    }

    var amountMinor: Int {
        PayViewModel.minor(from: amountText)
    }

    /// "£12.5" while typing, "£0" when empty.
    var amountDisplay: String {
        "£" + (amountText.isEmpty ? "0" : amountText)
    }

    var exceedsPerPaymentLimit: Bool {
        amountMinor > perPaymentLimitMinor
    }

    var referenceRemaining: Int {
        PayViewModel.referenceMaxLength - reference.count
    }

    var referenceIsValid: Bool {
        !reference.trimmingCharacters(in: .whitespaces).isEmpty && reference.count <= PayViewModel.referenceMaxLength
    }

    var targetCanReceive: Bool {
        target?.canReceive ?? false
    }

    var canPay: Bool {
        target != nil && targetCanReceive && amountMinor > 0 && !exceedsPerPaymentLimit && referenceIsValid && !isSubmitting
    }

    var payButtonTitle: String {
        let amount = Money(minor: amountMinor).formatted(compact: true)
        if let bank = myBankName { return "Pay \(amount) with \(bank)" }
        return "Pay \(amount)"
    }

    var inlineMessage: String? {
        if let error { return error.userMessage }
        if exceedsPerPaymentLimit { return "The most you can send in one payment is \(Money(minor: perPaymentLimitMinor).formatted(compact: true))." }
        if let target, !target.canReceive {
            if let until = target.coolingOffUntil {
                return "\(target.firstName) changed bank account recently and can receive again from \(until.quidReceiptDescription)."
            }
            return "\(target.firstName) hasn't linked a verified bank account yet, so they can't be paid."
        }
        return nil
    }

    var resultKind: PayResultKind {
        if let status = payment?.status {
            switch status {
            case .executed, .settled:
                return .paid
            case .failed, .cancelled:
                return .failed(status.failureMessage ?? "The payment didn't go through. Nothing has been sent.")
            case .created, .authorizing, .authorized:
                break
            }
        }
        switch outcome {
        case .cancelled:
            return .failed("You cancelled the payment in your bank app. Nothing has been sent.")
        case .failed(let message):
            return .failed(message)
        case .completed, .none:
            return .pending
        }
    }

    // MARK: - Choosing and typing

    func select(_ target: PayTarget) {
        self.target = target
        error = nil
        if path.last != .amount {
            path.append(.amount)
        }
    }

    func press(_ key: KeypadKey) {
        error = nil
        switch key {
        case .digit(let digit):
            let parts = amountText.split(separator: ".", omittingEmptySubsequences: false)
            if parts.count == 2 {
                guard parts[1].count < 2 else { return }
            } else {
                guard amountText.count < 5 else { return }
                if amountText == "0" { amountText = "" }
            }
            amountText.append(String(digit))
        case .point:
            guard !amountText.contains(".") else { return }
            amountText = amountText.isEmpty ? "0." : amountText + "."
        case .delete:
            guard !amountText.isEmpty else { return }
            amountText.removeLast()
        }
    }

    func setQuickAmount(_ minor: Int) {
        error = nil
        amountText = PayViewModel.text(fromMinor: minor)
    }

    // MARK: - Paying

    func submit() async {
        guard canPay, let target else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let response = try await environment.api.send(
                API.createPayment(CreatePaymentRequest(payeeUserId: target.userId, amountMinor: amountMinor, reference: reference.trimmingCharacters(in: .whitespaces)))
            )
            created = response
            error = nil
            if response.firstTimePayee {
                pendingFirstTime = response
            } else {
                await authorise(response)
            }
        } catch is CancellationError {
            return
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown(error.localizedDescription)
        }
    }

    /// Pay tapped on the sheet: remember it and let the sheet dismiss; `confirmFirstTime` runs from onDismiss.
    func acceptFirstTime() {
        confirmedFirstTime = pendingFirstTime
        pendingFirstTime = nil
    }

    func confirmFirstTime() async {
        guard let response = confirmedFirstTime else { return }
        confirmedFirstTime = nil
        await authorise(response)
    }

    /// The payment stays CREATED/AUTHORIZING on the server and expires with the bank; nothing has moved.
    func cancelFirstTime() {
        guard confirmedFirstTime == nil else { return }
        pendingFirstTime = nil
        created = nil
    }

    func authoriseAgain() async {
        guard let created else { return }
        await authorise(created)
    }

    private func authorise(_ response: PaymentCreateResponseDTO) async {
        isAuthorising = true
        // A backend running PAYMENT_PROVIDER=fake sends the payer to its own approval page, not to TrueLayer.
        let chosen: any PaymentAuthoriser = response.provider == "fake" ? environment.hostedPageAuthoriser : authoriser
        let outcome = await chosen.authorise(
            AuthorisationRequest(
                paymentId: response.paymentId,
                providerPaymentId: response.tlPaymentId,
                resourceToken: response.resourceToken,
                authorisationUrl: response.authorisationUrl.flatMap(URL.init(string:)),
                returnURL: AppConfig.paymentReturnURL
            )
        )
        isAuthorising = false
        self.outcome = outcome
        payment = response.payment
        if path.last != .result {
            path.append(.result)
        }
        startPolling()
    }

    // MARK: - Result

    /// Polls GET /payments/:id until the server says paid or failed, or the window runs out (spec: 3 s for 60 s).
    func startPolling() {
        pollTask?.cancel()
        pollingTimedOut = false
        pollTask = Task { [weak self] in
            let started = ContinuousClock.now
            while let self, !Task.isCancelled {
                await self.refreshPayment()
                if let status = self.payment?.status, PayViewModel.isResolved(status) { return }
                if ContinuousClock.now - started >= self.pollTimeout {
                    self.pollingTimedOut = true
                    return
                }
                try? await Task.sleep(for: self.pollInterval)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refreshPayment() async {
        guard let id = created?.paymentId else { return }
        do {
            payment = try await environment.api.send(API.payment(id: id))
        } catch {
            // Keep the last known state; the next tick tries again.
        }
    }

    /// Back to the amount screen after a failure, keeping the person and amount.
    func tryAgain() {
        stopPolling()
        created = nil
        outcome = nil
        payment = nil
        pollingTimedOut = false
        if path.last == .result { path.removeLast() }
    }

    func done() {
        stopPolling()
        finished = true
    }

    // MARK: - Helpers

    static func isResolved(_ status: PaymentStatus) -> Bool {
        switch status {
        case .executed, .settled, .failed, .cancelled: return true
        case .created, .authorizing, .authorized: return false
        }
    }

    static func defaultReference(for displayName: String?) -> String {
        let first = displayName?.split(whereSeparator: { $0.isWhitespace }).first.map { cleanReference(String($0)) } ?? ""
        return cleanReference(first.isEmpty ? "From Quid" : "From \(first)")
    }

    /// Faster Payments-safe: letters, digits, space and & . / - ; at most 18 characters. Accents fold rather than
    /// vanish ("José" -> "Jose"); letters with no ASCII form are dropped.
    static func cleanReference(_ raw: String) -> String {
        let folded = raw.folding(options: .diacriticInsensitive, locale: nil)
        let allowed = folded.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == " " || "&./-".contains($0)) }
        return String(allowed.prefix(referenceMaxLength))
    }

    static func minor(from text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        let pounds = Int(parts.first ?? "") ?? 0
        var pence = 0
        if parts.count == 2 {
            let fraction = String(parts[1]).padding(toLength: 2, withPad: "0", startingAt: 0)
            pence = Int(fraction) ?? 0
        }
        return pounds * 100 + pence
    }

    static func text(fromMinor minor: Int) -> String {
        let pounds = minor / 100
        let pence = minor % 100
        return pence == 0 ? String(pounds) : "\(pounds).\(String(format: "%02d", pence))"
    }
}
