import Foundation

enum PaymentDirection: Equatable {
    case sent, received
}

extension PaymentDTO {
    func direction(for currentUserId: String) -> PaymentDirection {
        payerUserId == currentUserId ? .sent : .received
    }

    /// Signed amount from the current user's point of view.
    func signedMoney(for currentUserId: String) -> Money {
        let sign = direction(for: currentUserId) == .sent ? -1 : 1
        return Money(minor: amountMinor * sign, currency: currency)
    }
}

extension PaymentStatus {
    /// Three words the user sees: Paid / Pending / Failed (plus Cancelled).
    var pillText: String {
        switch self {
        case .settled, .executed: return "Paid"
        case .created, .authorizing, .authorized: return "Pending"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    var pillTone: StatusPill.Tone {
        switch self {
        case .settled, .executed: return .success
        case .created, .authorizing, .authorized: return .pending
        case .failed, .cancelled: return .failure
        }
    }

    /// What to tell the user about a failed or cancelled payment. `failureReason` is a provider code kept for
    /// support and logs, never shown verbatim.
    var failureMessage: String? {
        switch self {
        case .cancelled: return "You cancelled the payment. Nothing has been sent."
        case .failed: return "The payment didn't go through. Nothing has been sent."
        case .created, .authorizing, .authorized, .executed, .settled: return nil
        }
    }

    /// Final states never change again; pending ones are polled or updated by webhooks.
    var isFinal: Bool {
        switch self {
        case .settled, .failed, .cancelled: return true
        case .created, .authorizing, .authorized, .executed: return false
        }
    }
}

extension CopStatus {
    var label: String {
        switch self {
        case .match: return "Verified"
        case .closeMatch: return "Name needs confirming"
        case .noMatch: return "Name doesn't match"
        case .unchecked: return "Not verified yet"
        }
    }

    var pillTone: StatusPill.Tone {
        switch self {
        case .match: return .success
        case .closeMatch, .unchecked: return .pending
        case .noMatch: return .failure
        }
    }
}

extension CounterpartyDTO {
    var firstName: String {
        String(displayName.split(whereSeparator: { $0.isWhitespace }).first ?? Substring(displayName))
    }
}

extension OrgKind {
    var label: String {
        switch self {
        case .society: return "Society"
        case .club: return "Club"
        case .flat: return "Flat"
        case .other: return "Group"
        }
    }
}
