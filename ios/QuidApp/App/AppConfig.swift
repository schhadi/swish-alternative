import Foundation

enum AppConfig {
    /// Backend base URL. A scheme's QUID_API_BASE_URL environment variable wins, but only applies when Xcode launches
    /// the app; an installed build (a phone, TestFlight) reads the QuidAPIBaseURL key in Info.plist, for example the
    /// Fly.io sandbox (docs/RUNBOOK.md). Neither set: http://localhost:3000.
    static var apiBaseURL: URL {
        apiBaseURL(
            environment: ProcessInfo.processInfo.environment["QUID_API_BASE_URL"],
            infoPlist: Bundle.main.object(forInfoDictionaryKey: "QuidAPIBaseURL") as? String
        )
    }

    static func apiBaseURL(environment: String?, infoPlist: String?) -> URL {
        for candidate in [environment, infoPlist] {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty, let url = URL(string: trimmed), url.scheme != nil { return url }
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
