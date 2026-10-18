import Foundation
import Observation

/// App-wide dependencies, injected once at the root with `.environment(...)`.
@MainActor
@Observable
final class AppEnvironment {
    private(set) var api: APIClient
    private(set) var session: SessionStore
    private(set) var isMock: Bool

    init(api: APIClient, session: SessionStore, isMock: Bool) {
        self.api = api
        self.session = session
        self.isMock = isMock
    }

    /// Live backend (localhost:3000) unless MockMode is switched on for this launch.
    static func bootstrap() -> AppEnvironment {
        if MockMode.isEnabled {
            return demo()
        }
        let store = KeychainTokenStore()
        return AppEnvironment(
            api: APIClient(baseURL: AppConfig.apiBaseURL, tokenStore: store),
            session: SessionStore(store: store),
            isMock: false
        )
    }

    /// Canned data, already signed in. Used by MockMode, previews and tests.
    static func demo() -> AppEnvironment {
        let store = InMemoryTokenStore(token: MockMode.sessionToken)
        return AppEnvironment(api: .mock(tokenStore: store), session: SessionStore(store: store), isMock: true)
    }

    /// Switches a live build into the demo ("Explore the demo" on the welcome screen).
    func enterDemoMode() {
        let store = InMemoryTokenStore(token: MockMode.sessionToken)
        api = .mock(tokenStore: store)
        session = SessionStore(store: store)
        isMock = true
    }
}
