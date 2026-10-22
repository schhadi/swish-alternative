import Foundation
import Observation

/// Values carried into the request flow, e.g. from "Split this with others" after a payment.
struct RequestPrefill: Hashable, Identifiable, Sendable {
    var totalMinor: Int
    var title: String
    /// The user paid the bill, so their own share comes out of it.
    var includeMe: Bool

    var id: String { "\(totalMinor)-\(title)-\(includeMe)" }
}

/// Request money from one or several people: pick them, split an amount, give it a title (docs/SPEC.md section 8,
/// screen 5). Always creates a split, even for one person, so progress, nudges and the link work the same way.
@MainActor
@Observable
final class RequestViewModel {
    enum Step: Hashable {
        case amount
        case sent(SplitDTO)
    }

    enum Mode: String, CaseIterable, Identifiable {
        case equal = "Split equally"
        case custom = "Custom amounts"

        var id: String { rawValue }
    }

    struct Person: Hashable, Identifiable {
        let userId: String
        let displayName: String

        var id: String { userId }
    }

    static let maxPeople = 20
    static let titleMaxLength = 40
    static let maxTotalMinor = 1_000_000
    static let fallbackPerPersonLimitMinor = 25000

    var path: [Step] = []
    private(set) var people: [Person] = []
    var mode: Mode = .equal {
        didSet { if mode != oldValue { error = nil } }
    }
    /// The bill as typed on the keypad (equal mode): "60", "12.5".
    private(set) var totalText = ""
    var includeMe = false
    /// Per-person amounts as typed (custom mode), by user id.
    private(set) var customText: [String: String] = [:]
    var title = "" {
        didSet {
            let clipped = String(title.prefix(RequestViewModel.titleMaxLength))
            if clipped != title { title = clipped }
        }
    }
    private(set) var selectionMessage: String?
    private(set) var isSubmitting = false
    private(set) var error: AppError?
    private(set) var created: SplitDTO?
    private(set) var finished = false

    private let environment: AppEnvironment

    init(environment: AppEnvironment, prefill: RequestPrefill? = nil) {
        self.environment = environment
        if let prefill {
            totalText = prefill.totalMinor > 0 ? PayViewModel.text(fromMinor: prefill.totalMinor) : ""
            title = String(prefill.title.prefix(RequestViewModel.titleMaxLength))
            includeMe = prefill.includeMe
        }
    }

    var api: APIClient { environment.api }

    var perPersonLimitMinor: Int {
        environment.profile?.limits.perPaymentMinor ?? RequestViewModel.fallbackPerPersonLimitMinor
    }

    // MARK: - People

    func isSelected(_ userId: String) -> Bool {
        people.contains { $0.userId == userId }
    }

    func toggle(_ contact: RegisteredContactDTO) {
        selectionMessage = nil
        if let index = people.firstIndex(where: { $0.userId == contact.userId }) {
            people.remove(at: index)
            customText[contact.userId] = nil
            return
        }
        guard people.count < RequestViewModel.maxPeople else {
            selectionMessage = "You can ask up to \(RequestViewModel.maxPeople) people at once."
            return
        }
        people.append(Person(userId: contact.userId, displayName: contact.displayName))
    }

    var namesLine: String {
        NameList.firstNames(people.map(\.displayName))
    }

    var continueTitle: String {
        switch people.count {
        case 0: return "Choose who to ask"
        case 1: return "Continue with \(namesLine)"
        default: return "Continue with \(people.count) people"
        }
    }

    func continueToAmount() {
        guard !people.isEmpty else { return }
        if path.last != .amount { path.append(.amount) }
    }

    // MARK: - Amounts

    func press(_ key: PayViewModel.KeypadKey) {
        error = nil
        totalText = PayViewModel.applying(key, to: totalText)
    }

    func amountText(for userId: String) -> String {
        customText[userId] ?? ""
    }

    func setAmountText(_ raw: String, for userId: String) {
        error = nil
        let cleaned = PayViewModel.sanitisedAmount(raw)
        if customText[userId] != cleaned { customText[userId] = cleaned }
    }

    var enteredTotalMinor: Int {
        PayViewModel.minor(from: totalText)
    }

    /// What each person is asked for, in the order they were picked.
    var shareAmounts: [Int] {
        switch mode {
        case .equal:
            return RequestViewModel.equalShares(totalMinor: enteredTotalMinor, people: people.count, includeMe: includeMe).each
        case .custom:
            return people.map { PayViewModel.minor(from: customText[$0.userId] ?? "") }
        }
    }

    var requestedMinor: Int {
        shareAmounts.reduce(0, +)
    }

    /// The user's own part of the bill: nothing in custom mode, an equal share (plus any odd pennies) otherwise.
    var myShareMinor: Int {
        mode == .equal ? RequestViewModel.equalShares(totalMinor: enteredTotalMinor, people: people.count, includeMe: includeMe).mine : 0
    }

    /// The bill the split describes: what was typed in equal mode, the sum of the shares in custom mode.
    var totalMinor: Int {
        mode == .equal ? enteredTotalMinor : requestedMinor
    }

    /// Splits a bill into whole pence. With the user included they absorb the odd pennies; without, the first
    /// people pay a penny more. Example: £10 three ways without me is 334, 333, 333.
    nonisolated static func equalShares(totalMinor: Int, people: Int, includeMe: Bool) -> (each: [Int], mine: Int) {
        guard people > 0, totalMinor > 0 else { return (Array(repeating: 0, count: max(people, 0)), 0) }
        let parts = people + (includeMe ? 1 : 0)
        let base = totalMinor / parts
        let remainder = totalMinor - base * parts
        if includeMe {
            return (Array(repeating: base, count: people), base + remainder)
        }
        return ((0..<people).map { base + ($0 < remainder ? 1 : 0) }, 0)
    }

    /// "£20 each" or "£3.33 to £3.34 each", plus the user's own share when they are in it.
    var summaryLine: String? {
        guard !people.isEmpty, totalMinor > 0 else { return nil }
        let amounts = shareAmounts
        guard let low = amounts.min(), let high = amounts.max(), high > 0 else { return nil }
        let each = low == high
            ? "\(Money(minor: low).formatted()) each"
            : "\(Money(minor: low).formatted()) to \(Money(minor: high).formatted()) each"
        let from = people.count == 1 ? "\(Money(minor: low).formatted()) from \(namesLine)" : "\(each) from \(namesLine)"
        if mode == .equal && includeMe {
            return "\(from) · your share \(Money(minor: myShareMinor).formatted())"
        }
        return from
    }

    var amountProblem: String? {
        let amounts = shareAmounts
        if amounts.contains(where: { $0 > perPersonLimitMinor }) {
            return "You can ask each person for up to \(Money(minor: perPersonLimitMinor).formatted(compact: true)), the most they can send in one payment."
        }
        if totalMinor > RequestViewModel.maxTotalMinor {
            return "A split can be for up to \(Money(minor: RequestViewModel.maxTotalMinor).formatted(compact: true))."
        }
        if mode == .equal, enteredTotalMinor > 0, amounts.contains(0) {
            return "That's less than 1p each. Enter a bigger amount."
        }
        return nil
    }

    var inlineMessage: String? {
        error?.userMessage ?? amountProblem
    }

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSubmit: Bool {
        !people.isEmpty
            && !trimmedTitle.isEmpty
            && shareAmounts.allSatisfy { $0 > 0 }
            && amountProblem == nil
            && !isSubmitting
    }

    var submitTitle: String {
        requestedMinor > 0 ? "Request \(Money(minor: requestedMinor).formatted(compact: true))" : "Request"
    }

    // MARK: - Sending

    func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        let shares = zip(people, shareAmounts).map { CreateSplitRequest.Share(userId: $0.userId, amountMinor: $1) }
        do {
            let split = try await api.send(API.createSplit(CreateSplitRequest(title: trimmedTitle, totalMinor: totalMinor, shares: shares)))
            created = split
            error = nil
            path.append(.sent(split))
        } catch is CancellationError {
            return
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown(error.localizedDescription)
        }
    }

    func done() {
        finished = true
    }
}
