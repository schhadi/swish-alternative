import Foundation
import Observation

/// App-wide dependencies and the signed-in profile, injected once at the root with `.environment(...)`.
@MainActor
@Observable
final class AppEnvironment {
    private(set) var api: APIClient
    private(set) var session: SessionStore
    private(set) var isMock: Bool

    /// Loaded after sign-in. Decides whether onboarding still has steps to run.
    private(set) var profile: MeDTO?
    private(set) var profileError: AppError?
    private(set) var isLoadingProfile = false
    private(set) var hasLoadedProfile = false

    /// True from "Get started" (or a resumed step) until the contacts explainer is dismissed.
    private(set) var onboardingInProgress = false
    /// Per-device flags (UserDefaults): trivial state only, per docs/SPEC.md section 2.
    private(set) var contactsExplainerSeen: Bool
    private(set) var bankLinkSkipped: Bool

    private let defaults: UserDefaults

    private enum Keys {
        static let contactsExplainerSeen = "onboarding.contactsExplainerSeen"
        static let bankLinkSkipped = "onboarding.bankLinkSkipped"
    }

    init(api: APIClient, session: SessionStore, isMock: Bool, defaults: UserDefaults = .standard) {
        self.api = api
        self.session = session
        self.isMock = isMock
        self.defaults = defaults
        contactsExplainerSeen = defaults.bool(forKey: Keys.contactsExplainerSeen)
        bankLinkSkipped = defaults.bool(forKey: Keys.bankLinkSkipped)
    }

    /// Live backend (localhost:3000) unless MockMode is switched on for this launch.
    static func bootstrap() -> AppEnvironment {
        if MockMode.isEnabled {
            return demo(signedIn: !MockMode.startsSignedOut)
        }
        let store = KeychainTokenStore()
        return AppEnvironment(
            api: APIClient(baseURL: AppConfig.apiBaseURL, tokenStore: store),
            session: SessionStore(store: store),
            isMock: false
        )
    }

    /// Canned data. `signedIn` = an existing, fully onboarded demo user; otherwise the welcome screen with a fresh mock user.
    static func demo(signedIn: Bool = true, defaults: UserDefaults = .standard) -> AppEnvironment {
        let store = InMemoryTokenStore(token: signedIn ? MockMode.sessionToken : nil)
        MockServer.shared.reset(signedIn: signedIn)
        let environment = AppEnvironment(api: .mock(tokenStore: store), session: SessionStore(store: store), isMock: true, defaults: defaults)
        if !signedIn {
            environment.resetOnboardingFlags()
        }
        return environment
    }

    /// Switches a live build into the demo ("Explore the demo" on the welcome screen).
    func enterDemoMode() {
        let store = InMemoryTokenStore(token: MockMode.sessionToken)
        MockServer.shared.reset(signedIn: true)
        api = .mock(tokenStore: store)
        session = SessionStore(store: store)
        isMock = true
        profile = nil
        profileError = nil
        hasLoadedProfile = false
        onboardingInProgress = false
    }

    // MARK: - Profile

    func loadProfile() async {
        guard session.isSignedIn else { return }
        isLoadingProfile = true
        defer { isLoadingProfile = false }
        do {
            profile = try await api.send(API.me())
            profileError = nil
            hasLoadedProfile = true
        } catch is CancellationError {
            return
        } catch let appError as AppError {
            if appError == .unauthorized {
                session.signOut()
                profile = nil
            }
            profileError = appError
        } catch {
            profileError = .unknown(error.localizedDescription)
        }
    }

    /// Which onboarding step is still outstanding for the loaded profile, or nil when the user is fully set up.
    var pendingOnboardingStep: OnboardingStep? {
        guard let profile else { return nil }
        if profile.user.displayName.trimmingCharacters(in: .whitespaces).isEmpty { return .name }
        if profile.bankAccount == nil && !bankLinkSkipped { return .bank }
        if !contactsExplainerSeen { return .contacts }
        return nil
    }

    // MARK: - Session and onboarding transitions

    func startOnboarding() {
        onboardingInProgress = true
    }

    func cancelOnboarding() {
        onboardingInProgress = false
    }

    /// Called by the OTP step once the backend has issued a token.
    func signIn(token: String) throws {
        try session.signIn(token: token)
        profile = nil
        profileError = nil
        hasLoadedProfile = false
    }

    func finishOnboarding() async {
        onboardingInProgress = false
        await loadProfile()
    }

    func markContactsExplainerSeen() {
        contactsExplainerSeen = true
        defaults.set(true, forKey: Keys.contactsExplainerSeen)
    }

    func markBankLinkSkipped() {
        bankLinkSkipped = true
        defaults.set(true, forKey: Keys.bankLinkSkipped)
    }

    /// After a bank account is linked from Home or Me, the skip no longer applies.
    func bankAccountLinked() {
        bankLinkSkipped = false
        defaults.set(false, forKey: Keys.bankLinkSkipped)
    }

    func signOut() async {
        _ = try? await api.send(API.logout())
        session.signOut()
        profile = nil
        profileError = nil
        hasLoadedProfile = false
        onboardingInProgress = false
        resetOnboardingFlags()
    }

    private func resetOnboardingFlags() {
        contactsExplainerSeen = false
        bankLinkSkipped = false
        defaults.removeObject(forKey: Keys.contactsExplainerSeen)
        defaults.removeObject(forKey: Keys.bankLinkSkipped)
    }
}

/// The screens of onboarding (docs/SPEC.md section 8, screen 1). Also used to resume after the app was killed.
enum OnboardingStep: Hashable {
    case phone, code, name, bank, copResult, contacts
}
