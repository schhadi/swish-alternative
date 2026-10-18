import Foundation
import Observation

/// The signed-in session. The token itself lives in the Keychain (or memory in MockMode).
@MainActor
@Observable
final class SessionStore {
    private(set) var token: String?
    private let store: any TokenStore

    init(store: any TokenStore) {
        self.store = store
        self.token = store.load()
    }

    var isSignedIn: Bool {
        token != nil
    }

    func signIn(token: String) throws {
        try store.save(token)
        self.token = token
    }

    func signOut() {
        store.clear()
        token = nil
    }
}
