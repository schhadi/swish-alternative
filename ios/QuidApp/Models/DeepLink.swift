import Foundation

/// Links that open a screen: quid://split/<id> from the split page's "Open in Quid" button, and the shared
/// https://<domain>/s/<id> link itself once universal links are set up (Phase 5). Anything else is not ours.
enum DeepLink: Hashable, Identifiable, Sendable {
    case split(id: String)

    var id: String {
        switch self {
        case .split(let id): return "split-\(id)"
        }
    }

    init?(url: URL) {
        let parts = url.pathComponents.filter { $0 != "/" }
        let candidate: String?
        switch url.scheme?.lowercased() {
        case "quid":
            candidate = url.host()?.lowercased() == "split" && parts.count == 1 ? parts[0] : nil
        case "https", "http":
            candidate = parts.count == 2 && parts[0] == "s" ? parts[1] : nil
        default:
            candidate = nil
        }
        guard let id = candidate, DeepLink.isValidId(id) else { return nil }
        self = .split(id: id)
    }

    /// Server ids are UUIDs; anything longer or with other characters is refused before it reaches a URL path.
    static func isValidId(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }
}
