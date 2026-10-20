import Foundation

/// Who the user is paying, as far as the app knows before POST /payments confirms it.
struct PayTarget: Hashable, Identifiable, Sendable {
    let userId: String
    let displayName: String
    /// Their bank, when the directory told us; nil when the target came from the activity feed.
    let bankName: String?
    let canReceive: Bool
    let coolingOffUntil: Date?

    var id: String { userId }

    var firstName: String {
        String(displayName.split(whereSeparator: { $0.isWhitespace }).first ?? Substring(displayName))
    }

    init(userId: String, displayName: String, bankName: String? = nil, canReceive: Bool = true, coolingOffUntil: Date? = nil) {
        self.userId = userId
        self.displayName = displayName
        self.bankName = bankName
        self.canReceive = canReceive
        self.coolingOffUntil = coolingOffUntil
    }

    init(registered: RegisteredContactDTO) {
        self.init(
            userId: registered.userId,
            displayName: registered.displayName,
            bankName: registered.bankName,
            canReceive: registered.canReceive,
            coolingOffUntil: registered.coolingOffUntil
        )
    }
}

/// What the result screen shows, derived from the server's status first and the bank's outcome second.
enum PayResultKind: Equatable {
    case paid
    case pending
    case failed(String)
}
