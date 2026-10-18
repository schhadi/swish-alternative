import Foundation

/// An amount in minor units (pence). GBP only in v1; the currency is carried so the server can be the source of truth.
struct Money: Hashable, Codable, Sendable {
    var minor: Int
    var currency: String

    init(minor: Int, currency: String = "GBP") {
        self.minor = minor
        self.currency = currency
    }

    static func pounds(_ pounds: Int) -> Money {
        Money(minor: pounds * 100)
    }

    var isNegative: Bool { minor < 0 }

    /// "£12.50". `compact` drops ".00" on whole amounts ("£12"). Negative amounts use a real minus sign.
    func formatted(compact: Bool = false, explicitPlus: Bool = false) -> String {
        let absolute = abs(minor)
        let pounds = absolute / 100
        let pence = absolute % 100
        let sign = isNegative ? "−" : (explicitPlus && minor > 0 ? "+" : "")
        let symbol = currency == "GBP" ? "£" : "\(currency) "
        let poundsText = Money.grouped(pounds)
        if compact && pence == 0 {
            return "\(sign)\(symbol)\(poundsText)"
        }
        return "\(sign)\(symbol)\(poundsText).\(String(format: "%02d", pence))"
    }

    /// 1250 -> "1,250". Avoids NumberFormatter so output is identical on every locale.
    static func grouped(_ value: Int) -> String {
        let digits = Array(String(value))
        var output: [Character] = []
        for (index, digit) in digits.enumerated() {
            let remaining = digits.count - index
            if index > 0 && remaining % 3 == 0 {
                output.append(",")
            }
            output.append(digit)
        }
        return String(output)
    }
}
