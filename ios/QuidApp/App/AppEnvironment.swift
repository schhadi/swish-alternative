import Foundation
import Observation

/// App-wide dependencies and the signed-in profile, injected once at the root with `.environment(...)`.
@MainActor
@Observable
final class AppEnvironment {
    private(set) var api: APIClient
    private(set) var session: SessionStore
    private(set) var isMock: Bool
    /// Bank authorisation and the address book: real in a live build, canned in MockMode.
    private(set) var paymentAuthoriser: any PaymentAuthoriser
    /// Used for payments the backend created with its fake provider: their approval page is a web page, never the SDK.
    private(set) var hostedPageAuthoriser: any PaymentAuthoriser
    private(set) var contactSource: any ContactSource

    /// Loaded after sign-in. Decides whether onboarding still has steps to run.
    private(set) var profile: MeDTO?
    private(set) var profileError: AppError?
    private(set) var isLoadingProfile = false
    private(set) var hasLoadedProfile = false

    /// True from "Get started" (or a resumed step) until the contacts explainer is dismissed.
    private(set) var onboardingInProgress = false
    /// A link opened from outside (a split's "Open in Quid"). Shown once the main tabs are up; cleared when dismissed.
    var pendingDeepLink: DeepLink?
    /// Per-device flags (UserDefaults): trivial state only, per docs/SPEC.md section 2.
    private(set) var contactsExplainerSeen: Bool
    private(set) var bankLinkSkipped: Bool

    private let defaults: UserDefaults

    private enum Keys {
        static let contactsExplainerSeen = "onboarding.contactsExplainerSeen"
        static let bankLinkSkipped = "onboarding.bankLinkSkipped"
    }

    init(
        api: APIClient,
        session: SessionStore,
        isMock: Bool,
        defaults: UserDefaults = .standard,
        paymentAuthoriser: (any PaymentAuthoriser)? = nil,
        contactSource: (any ContactSource)? = nil
    ) {
        self.api = api
        self.session = session
        self.isMock = isMock
        self.defaults = defaults
        let authoriser = paymentAuthoriser ?? (isMock ? MockPaymentAuthoriser() : AppEnvironment.liveAuthoriser())
        self.paymentAuthoriser = authoriser
        self.hostedPageAuthoriser = isMock ? authoriser : WebPaymentAuthoriser()
        self.contactSource = contactSource ?? (isMock ? MockContactSource() : ContactsService())
        contactsExplainerSeen = defaults.bool(forKey: Keys.contactsExplainerSeen)
        bankLinkSkipped = defaults.bool(forKey: Keys.bankLinkSkipped)
    }

    /// Live backend (localhost:3000) unless MockMode is switched on for this launch.
    static func bootstrap() -> AppEnvironment {
        if MockMode.isEnabled {
            return demo(signedIn: !MockMode.startsSignedOut)
        }
        let store = KeychainTokenStore()
        let relay = SessionEndRelay()
        let environment = AppEnvironment(
            api: APIClient(baseURL: AppConfig.apiBaseURL, tokenStore: store, onUnauthorized: { relay.fire() }),
            session: SessionStore(store: store),
            isMock: false
        )
        relay.attach(environment)
        return environment
    }

    /// Canned data. `signedIn` = an existing, fully onboarded demo user; otherwise the welcome screen with a fresh mock user.
    static func demo(signedIn: Bool = true, defaults: UserDefaults = .standard) -> AppEnvironment {
        let store = InMemoryTokenStore(token: signedIn ? MockMode.sessionToken : nil)
        MockServer.shared.reset(signedIn: signedIn)
        let relay = SessionEndRelay()
        let environment = AppEnvironment(
            api: .mock(tokenStore: store, onUnauthorized: { relay.fire() }),
            session: SessionStore(store: store),
            isMock: true,
            defaults: defaults
        )
        relay.attach(environment)
        if signedIn {
            environment.markDemoUserOnboarded()
        } else {
            environment.resetOnboardingFlags()
        }
        return environment
    }

    /// The SDK when the package is linked and not overridden for debugging; the hosted page otherwise.
    private static func liveAuthoriser() -> any PaymentAuthoriser {
        #if canImport(TrueLayerSDK)
        if !AppConfig.useHostedPaymentPage {
            return TrueLayerPaymentAuthoriser(environment: AppConfig.truelayerEnvironment)
        }
        #endif
        return WebPaymentAuthoriser()
    }

    /// Switches a live build into the demo ("Explore the demo" on the welcome screen).
    func enterDemoMode() {
        let store = InMemoryTokenStore(token: MockMode.sessionToken)
        MockServer.shared.reset(signedIn: true)
        let relay = SessionEndRelay()
        api = .mock(tokenStore: store, onUnauthorized: { relay.fire() })
        relay.attach(self)
        session = SessionStore(store: store)
        isMock = true
        paymentAuthoriser = MockPaymentAuthoriser()
        hostedPageAuthoriser = paymentAuthoriser
        contactSource = MockContactSource()
        profile = nil
        profileError = nil
        hasLoadedProfile = false
        onboardingInProgress = false
        markDemoUserOnboarded()
    }

    /// The demo user finished onboarding long ago, so the explainer is treated as seen for this launch only.
    /// Nothing is written to UserDefaults: a live sign-in on the same device still gets the explainer once.
    private func markDemoUserOnboarded() {
        contactsExplainerSeen = true
        bankLinkSkipped = false
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
                sessionEnded()
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

    /// After a bank account is linked (onboarding, Home or Me). The profile is refreshed first and the skip flag only
    /// cleared once it shows the account, so RootView never sees "no bank, not skipped" and reopens the bank step.
    func bankAccountLinked() async {
        await loadProfile()
        guard profile?.bankAccount != nil else { return }
        bankLinkSkipped = false
        defaults.set(false, forKey: Keys.bankLinkSkipped)
    }

    func signOut() async {
        _ = try? await api.send(API.logout())
        sessionEnded()
    }

    /// The token is no longer valid (sign-out, expiry, logged out elsewhere, account deleted): forget the account on this
    /// device, including a half-finished onboarding, so RootView shows Welcome and nothing leaks to the next account.
    func sessionEnded() {
        session.signOut()
        pendingDeepLink = nil
        profile = nil
        profileError = nil
        hasLoadedProfile = false
        onboardingInProgress = false
        resetOnboardingFlags()
    }

    /// Forgets the per-device flags, as a reinstall would. Called on sign-out.
    func resetOnboardingFlags() {
        contactsExplainerSeen = false
        bankLinkSkipped = false
        defaults.removeObject(forKey: Keys.contactsExplainerSeen)
        defaults.removeObject(forKey: Keys.bankLinkSkipped)
    }
}

/// Hands APIClient's 401 callback to the environment it belongs to. The client is created before the environment
/// exists, so the relay is attached one step later; it only ever calls into the environment on the main actor.
private final class SessionEndRelay: @unchecked Sendable {
    private weak var environment: AppEnvironment?

    @MainActor
    func attach(_ environment: AppEnvironment) {
        self.environment = environment
    }

    func fire() {
        Task { @MainActor [weak self] in self?.environment?.sessionEnded() }
    }
}

/// The screens of onboarding (docs/SPEC.md section 8, screen 1). Also used to resume after the app was killed.
enum OnboardingStep: Hashable {
    case phone, code, name, bank, copResult, contacts
}
