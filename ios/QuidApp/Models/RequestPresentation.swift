import Foundation

extension RequestStatus {
    /// Open / Paid / Declined / Expired / Cancelled, as pills and list subtitles show them.
    var pillText: String {
        switch self {
        case .pending: return "Open"
        case .paid: return "Paid"
        case .declined: return "Declined"
        case .expired: return "Expired"
        case .cancelled: return "Cancelled"
        }
    }

    var pillTone: StatusPill.Tone {
        switch self {
        case .pending: return .pending
        case .paid: return .success
        case .declined: return .failure
        case .expired, .cancelled: return .neutral
        }
    }
}

extension PaymentRequestDTO {
    /// What the request is for: the split's title when it is a share of one, otherwise its reference.
    var title: String {
        splitTitle ?? reference
    }

    var payerName: String {
        payer?.displayName ?? "Someone"
    }
}

extension SplitShareDTO {
    var firstName: String {
        String(displayName.split(whereSeparator: { $0.isWhitespace }).first ?? Substring(displayName))
    }

    /// Open and not nudged in the last 24 hours.
    func canNudge(at now: Date = Date()) -> Bool {
        guard status == .pending else { return false }
        guard let next = nextReminderAt else { return true }
        return next <= now
    }
}

extension SplitDTO {
    var linkURL: URL? {
        URL(string: link)
    }

    /// Shares that are open and due a reminder.
    func sharesDueAReminder(at now: Date = Date()) -> [SplitShareDTO] {
        shares.filter { $0.canNudge(at: now) }
    }

    var progressLine: String {
        "\(paidCount) of \(shareCount) paid"
    }

    /// Open while anyone can still pay; Cancelled when every request was withdrawn; Done otherwise.
    var statusText: String {
        if !isComplete { return "Open" }
        return isWithdrawn ? "Cancelled" : "Done"
    }

    var statusTone: StatusPill.Tone {
        if !isComplete { return .pending }
        return isWithdrawn ? .neutral : .success
    }

    private var isWithdrawn: Bool {
        !shares.isEmpty && shares.allSatisfy { $0.status == .cancelled }
    }
}

/// "Priya", "Priya and Tom", "Priya, Tom and Amara", "Priya, Tom and 3 others".
enum NameList {
    static func firstNames(_ names: [String]) -> String {
        let firsts = names.map { String($0.split(whereSeparator: { $0.isWhitespace }).first ?? Substring($0)) }
        switch firsts.count {
        case 0: return ""
        case 1: return firsts[0]
        case 2: return "\(firsts[0]) and \(firsts[1])"
        case 3: return "\(firsts[0]), \(firsts[1]) and \(firsts[2])"
        default: return "\(firsts[0]), \(firsts[1]) and \(firsts.count - 2) others"
        }
    }
}
