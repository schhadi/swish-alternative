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
    /// Paying a request someone sent: the person, amount and reference come from it and cannot be changed.
    let request: PaymentRequestDTO?
    /// Paying one's share of a collection: the organisation, amount and reference are fixed the same way.
    let collectionDue: CollectionDueDTO?
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
    /// The cancel call made when the first-time sheet is dismissed; kept so tests can wait for it.
    private(set) var cancelTask: Task<Void, Never>?

    init(environment: AppEnvironment, target: PayTarget?, request: PaymentRequestDTO? = nil, collectionDue: CollectionDueDTO? = nil, authoriser: (any PaymentAuthoriser)? = nil) {
        self.environment = environment
        self.authoriser = authoriser ?? environment.paymentAuthoriser
        self.request = request
        self.collectionDue = collectionDue
        if let collectionDue {
            self.target = PayTarget(userId: "collection-\(collectionDue.collectionId)", displayName: collectionDue.organisationName)
            rootIsPicker = false
            amountText = PayViewModel.text(fromMinor: collectionDue.amountPerPersonMinor)
            // The server sets the reference from the title, falling back the same way for titles with no plain letters.
            let cleaned = PayViewModel.cleanReference(collectionDue.title).trimmingCharacters(in: .whitespaces)
            reference = cleaned.isEmpty ? "Quid split" : cleaned
        } else if let request {
            self.target = PayTarget(userId: request.requesterUserId, displayName: request.requester.displayName)
            rootIsPicker = false
            amountText = PayViewModel.text(fromMinor: request.amountMinor)
            reference = request.reference
        } else {
            self.target = target
            rootIsPicker = target == nil
            reference = PayViewModel.defaultReference(for: environment.profile?.user.displayName)
        }
    }

    var isPayingRequest: Bool { request != nil }
    var isPayingCollection: Bool { collectionDue != nil }
    /// A request or a collection share: the amount and reference can't be changed.
    var isFixedAmount: Bool { request != nil || collectionDue != nil }

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
        // A request or a collection brings its own reference, which the server sets; only a typed one is checked here.
        target != nil && targetCanReceive && amountMinor > 0 && !exceedsPerPaymentLimit && (isFixedAmount || referenceIsValid) && !isSubmitting
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
                // Cancelled by the app because the bank's page failed: the reason the payer saw is the one to keep.
                if status == .cancelled, case .failed(let message) = outcome { return .failed(message) }
                return .failed(status.failureMessage ?? "The payment didn't go through. Nothing has been sent.")
            case .created, .authorizing, .authorized:
                break
            }
        }
        switch outcome {
        case .cancelled:
            return .failed(PaymentStatus.cancelled.failureMessage ?? "You cancelled the payment. Nothing has been sent.")
        case .failed(let message):
            return .failed(message)
        case .completed, .none:
            return .pending
        }
    }

    /// "Split this with others" after paying: the amount as the bill (the user paid it, so their own share is in it)
    /// and the reference as the title unless it is the default "From <name>". Not offered for a paid request.
    var splitPrefill: RequestPrefill? {
        guard !isFixedAmount, let payment else { return nil }
        let isDefault = payment.reference == PayViewModel.defaultReference(for: environment.profile?.user.displayName)
        return RequestPrefill(totalMinor: payment.amountMinor, title: isDefault ? "" : payment.reference, includeMe: true)
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
        // A request or a collection fixes the amount.
        guard !isFixedAmount else { return }
        error = nil
        amountText = PayViewModel.applying(key, to: amountText)
    }

    func setQuickAmount(_ minor: Int) {
        guard !isFixedAmount else { return }
        error = nil
        amountText = PayViewModel.text(fromMinor: minor)
    }

    // MARK: - Paying

    func submit() async {
        guard canPay, let target else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let endpoint: Endpoint<PaymentCreateResponseDTO>
            if let collectionDue {
                endpoint = API.payCollection(PayCollectionBody(collectionId: collectionDue.collectionId, amountMinor: collectionDue.amountPerPersonMinor))
            } else if let request {
                endpoint = API.payRequest(PayRequestBody(requestId: request.id, amountMinor: request.amountMinor))
            } else {
                endpoint = API.createPayment(CreatePaymentRequest(payeeUserId: target.userId, amountMinor: amountMinor, reference: reference.trimmingCharacters(in: .whitespaces)))
            }
            let response = try await environment.api.send(endpoint)
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

    /// Nothing has moved. The server is asked to cancel the payment, so it stops counting against the payer's
    /// limits at once instead of when the bank lets it expire; if that call fails, the bank's expiry still ends it.
    func cancelFirstTime() {
        guard confirmedFirstTime == nil else { return }
        let paymentId = created?.paymentId
        pendingFirstTime = nil
        created = nil
        if let paymentId {
            let api = environment.api
            cancelTask = Task { _ = try? await api.send(API.cancelPayment(id: paymentId)) }
        }
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
        if outcome != .completed {
            // The payer backed out, or the bank's page never worked: release the amount now. A 409 means the bank
            // has it after all (approved or sent), which the poll below then shows.
            if let updated = try? await environment.api.send(API.cancelPayment(id: response.paymentId)) {
                payment = updated
            }
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

    /// The keypad's editing rule, shared with the request flow: at most five pounds digits and two decimals.
    static func applying(_ key: KeypadKey, to text: String) -> String {
        var text = text
        switch key {
        case .digit(let digit):
            let parts = text.split(separator: ".", omittingEmptySubsequences: false)
            if parts.count == 2 {
                guard parts[1].count < 2 else { return text }
            } else {
                guard text.count < 5 else { return text }
                if text == "0" { text = "" }
            }
            text.append(String(digit))
        case .point:
            guard !text.contains(".") else { return text }
            text = text.isEmpty ? "0." : text + "."
        case .delete:
            guard !text.isEmpty else { return text }
            text.removeLast()
        }
        return text
    }

    /// The same rule for a typed amount (the request flow's per-person fields): digits and one point, at most five
    /// pounds digits and two decimals. Anything else typed or pasted is dropped.
    static func sanitisedAmount(_ raw: String) -> String {
        var result = ""
        for character in raw {
            if character.isASCII, character.isNumber {
                result = applying(.digit(Int(String(character)) ?? 0), to: result)
            } else if character == "." || character == "," {
                result = applying(.point, to: result)
            }
        }
        return result
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
