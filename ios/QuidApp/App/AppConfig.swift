import Foundation

enum AppConfig {
    /// Backend base URL. Override with the QUID_API_BASE_URL environment variable in the scheme
    /// (for example an ngrok URL when running on a physical device).
    static var apiBaseURL: URL {
        if let override = ProcessInfo.processInfo.environment["QUID_API_BASE_URL"], let url = URL(string: override) {
            return url
        }
        return URL(string: "http://localhost:3000")!
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    // Placeholder legal pages until real ones exist (docs/DECISIONS.md).
    static let privacyURL = URL(string: "https://quid.example/privacy")!
    static let termsURL = URL(string: "https://quid.example/terms")!
    /// Shared with contacts who are not on Quid yet; real invite links arrive in Phase 3.
    static let inviteURL = URL(string: "https://quid.example/invite")!

    // MARK: Payments

    enum TrueLayerEnvironment {
        case sandbox, live
    }

    /// Where the bank returns the payer (registered in the TrueLayer Console; the scheme is in Info.plist).
    static let paymentReturnURL = URL(string: "quid://return/payment")!

    /// QUID_TRUELAYER_ENV=live switches the SDK to production; sandbox otherwise.
    static var truelayerEnvironment: TrueLayerEnvironment {
        ProcessInfo.processInfo.environment["QUID_TRUELAYER_ENV"] == "live" ? .live : .sandbox
    }

    /// QUID_HOSTED_PAGE=1 authorises through the hosted payment page in a web session instead of the SDK (debugging).
    static var useHostedPaymentPage: Bool {
        ProcessInfo.processInfo.environment["QUID_HOSTED_PAGE"] == "1"
    }
}
