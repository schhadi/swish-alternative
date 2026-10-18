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
}
