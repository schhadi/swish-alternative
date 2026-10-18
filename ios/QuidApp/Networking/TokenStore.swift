import Foundation
import Security

/// Where the session bearer token lives. Keychain in the real app, memory in MockMode and tests.
protocol TokenStore: AnyObject, Sendable {
    func load() -> String?
    func save(_ token: String) throws
    func clear()
}

enum KeychainError: Error {
    case unhandled(OSStatus)
}

final class KeychainTokenStore: TokenStore {
    private let service: String
    private let account = "session-token"

    init(service: String = (Bundle.main.bundleIdentifier ?? "com.quid.app") + ".session") {
        self.service = service
    }

    func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ token: String) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var attributes = base
        attributes[kSecValueData as String] = Data(token.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
    }

    func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?

    init(token: String? = nil) {
        self.token = token
    }

    func load() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return token
    }

    func save(_ token: String) throws {
        lock.lock()
        defer { lock.unlock() }
        self.token = token
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        token = nil
    }
}
