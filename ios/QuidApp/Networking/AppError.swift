import Foundation

/// Extra fields some backend errors carry (e.g. attempts left on a wrong one-time code).
struct APIErrorDetails: Equatable, Sendable {
    var attemptsRemaining: Int?
}

/// Every failure the UI can see. Views show `userMessage`; nothing else leaks to the screen.
enum AppError: Error, Equatable, Sendable {
    case offline
    case timeout
    case unauthorized
    case forbidden
    case notFound
    case rateLimited
    /// The request was rejected by validation (400 validation_error).
    case validation(String)
    /// The backend rejected the request with a stable code such as "otp_invalid" or "unknown_provider".
    case api(code: String, message: String, details: APIErrorDetails)
    case server(status: Int, message: String?)
    case decoding
    case unknown(String)

    var userMessage: String {
        switch self {
        case .offline: return "You're offline. Check your connection and try again."
        case .timeout: return "That took too long. Try again."
        case .unauthorized: return "Your session has expired. Sign in again."
        case .forbidden: return "You don't have access to that."
        case .notFound: return "We couldn't find that."
        case .rateLimited: return "Too many attempts. Wait a moment and try again."
        case .validation(let message): return message
        case .api(_, let message, _): return message
        case .server(_, let message): return message ?? "Something went wrong on our side. Try again in a moment."
        case .decoding: return "We got an unexpected response. Please update the app."
        case .unknown(let message): return message
        }
    }

    /// The backend's stable error code, when there is one.
    var code: String? {
        if case .api(let code, _, _) = self { return code }
        return nil
    }

    static func from(urlError: URLError) -> AppError {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .internationalRoamingOff:
            return .offline
        case .timedOut:
            return .timeout
        default:
            return .unknown(urlError.localizedDescription)
        }
    }
}
