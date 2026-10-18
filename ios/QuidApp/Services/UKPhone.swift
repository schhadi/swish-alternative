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

    /// Formats the national number as the user types it: "07700900123" -> "07700 900123". Keeps digits only.
    static func formatNationalAsTyped(_ raw: String) -> String {
        let digits = String(raw.filter(\.isNumber).prefix(11))
        guard digits.count > 5 else { return digits }
        return "\(digits.prefix(5)) \(digits.dropFirst(5))"
    }

    /// "+447700900123" -> "+44 7700 ***123"
    static func masked(_ phoneE164: String) -> String {
        guard phoneE164.count >= 7 else { return "***" }
        return "\(phoneE164.prefix(3)) \(phoneE164.dropFirst(3).prefix(4)) ***\(phoneE164.suffix(3))"
    }
}
