import CryptoKit
import Foundation

/// Client half of the directory hashing scheme (docs/DECISIONS.md, Phase 1): SHA-256 of the E.164 number.
/// The server peppers this with HMAC before matching, so raw numbers never leave the phone and the database
/// cannot be matched without the pepper.
enum PhoneHasher {
    static func clientHash(_ phoneE164: String) -> String {
        let digest = SHA256.hash(data: Data(phoneE164.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
