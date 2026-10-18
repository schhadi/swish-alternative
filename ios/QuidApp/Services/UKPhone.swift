import Foundation

/// UK phone numbers only in v1. These rules mirror backend/src/lib/phone.ts exactly; keep them in sync, because the
/// directory matches on hashes of the normalised number.
enum UKPhone {
    /// "07700 900123", "+44 7700 900123", "0044 7700 900123", "447700900123" -> "+447700900123"; anything else -> nil.
    static func normalise(_ input: String) -> String? {
        let compact = input.filter { !" -().".contains($0) }
        let national: String
        if compact.hasPrefix("+44") {
            national = String(compact.dropFirst(3))
        } else if compact.hasPrefix("0044") {
            national = String(compact.dropFirst(4))
        } else if compact.hasPrefix("44"), compact.count >= 11, compact.count <= 12 {
            national = String(compact.dropFirst(2))
        } else if compact.hasPrefix("0") {
            national = String(compact.dropFirst(1))
        } else {
            return nil
        }
        guard national.count == 9 || national.count == 10,
              national.allSatisfy(\.isNumber),
              national.allSatisfy(\.isASCII),
              let first = national.first, first != "0"
        else {
            return nil
        }
        return "+44" + national
    }

    /// "+447700900123" -> "+44 7700 900123"
    static func formatForDisplay(_ phoneE164: String) -> String {
        guard phoneE164.hasPrefix("+44"), phoneE164.count == 13 else { return phoneE164 }
        let national = phoneE164.dropFirst(3)
        return "+44 \(national.prefix(4)) \(national.dropFirst(4))"
    }

    /// Formats the number as the user types it. National input keeps digits only, at most 11: "07700900123" ->
    /// "07700 900123". International input ("+44…", "0044…", "44…", as autofill and pasting produce) keeps the
    /// country code instead of being cut to 11 digits, which would silently turn it into a different valid number:
    /// "+447700900123" -> "+44 7700 900123". `normalise` accepts both shapes.
    static func formatNationalAsTyped(_ raw: String) -> String {
        var digits = raw.filter(\.isNumber)
        var international = raw.trimmingCharacters(in: .whitespaces).hasPrefix("+")
        if digits.hasPrefix("0044") {
            digits = String(digits.dropFirst(2))
            international = true
        }
        // UK national numbers start with 0, so a leading 44 can only be the country code.
        if digits.hasPrefix("44") { international = true }
        if international {
            // Only +44 is accepted, but never drop digits: `normalise` rejects everything else.
            guard digits.hasPrefix("44") else { return "+" + digits }
            let national = String(digits.dropFirst(2).prefix(10))
            if national.isEmpty { return "+44" }
            if national.count <= 4 { return "+44 " + national }
            return "+44 \(national.prefix(4)) \(national.dropFirst(4))"
        }
        digits = String(digits.prefix(11))
        guard digits.count > 5 else { return digits }
        return "\(digits.prefix(5)) \(digits.dropFirst(5))"
    }

    /// "+447700900123" -> "+44 7700 ***123"
    static func masked(_ phoneE164: String) -> String {
        guard phoneE164.count >= 7 else { return "***" }
        return "\(phoneE164.prefix(3)) \(phoneE164.dropFirst(3).prefix(4)) ***\(phoneE164.suffix(3))"
    }
}
