import Foundation

extension RequestStatus {
    /// Open / Paid / Declined / Expired, as pills and list subtitles show them.
    var pillText: String {
        switch self {
        case .pending: return "Open"
        case .paid: return "Paid"
        case .declined: return "Declined"
        case .expired: return "Expired"
        }
    }

    var pillTone: StatusPill.Tone {
        switch self {
        case .pending: return .pending
        case .paid: return .success
        case .declined: return .failure
        case .expired: return .neutral
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
