import Foundation

/// Every failure the UI can see. Views show `userMessage`; nothing else leaks to the screen.
enum AppError: Error, Equatable, Sendable {
    case offline
    case timeout
    case unauthorized
    case forbidden
    case notFound
    case rateLimited
    case validation(String)
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
        case .server(_, let message): return message ?? "Something went wrong on our side. Try again in a moment."
        case .decoding: return "We got an unexpected response. Please update the app."
        case .unknown(let message): return message
        }
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
