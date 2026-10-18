import Foundation

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

/// Decoded for 204 / empty responses.
struct Empty: Decodable, Sendable {}

/// A typed request: the compiler knows what each call returns.
struct Endpoint<Response: Decodable>: Sendable {
    let method: HTTPMethod
    let path: String
    let query: [URLQueryItem]
    let body: (any Encodable & Sendable)?
    let requiresAuth: Bool

    init(
        method: HTTPMethod,
        path: String,
        query: [URLQueryItem] = [],
        body: (any Encodable & Sendable)? = nil,
        requiresAuth: Bool = true
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
        self.requiresAuth = requiresAuth
    }
}

enum PaymentRole: String, Sendable {
    case sent, received
}

/// Every backend call the app makes, in one place. Add endpoints here as phases land.
enum API {
    static func health() -> Endpoint<HealthDTO> {
        Endpoint(method: .get, path: "/health", requiresAuth: false)
    }

    static func me() -> Endpoint<MeDTO> {
        Endpoint(method: .get, path: "/me")
    }

    static func deleteAccount() -> Endpoint<Empty> {
        Endpoint(method: .delete, path: "/me")
    }

    static func payments(role: PaymentRole, limit: Int = 50) -> Endpoint<PaymentListDTO> {
        Endpoint(
            method: .get,
            path: "/payments",
            query: [URLQueryItem(name: "role", value: role.rawValue), URLQueryItem(name: "limit", value: String(limit))]
        )
    }

    static func payment(id: String) -> Endpoint<PaymentDTO> {
        Endpoint(method: .get, path: "/payments/\(id)")
    }

    static func incomingRequests() -> Endpoint<RequestListDTO> {
        Endpoint(method: .get, path: "/requests", query: [URLQueryItem(name: "role", value: "incoming")])
    }

    static func organisations() -> Endpoint<OrgListDTO> {
        Endpoint(method: .get, path: "/orgs")
    }

    static func collection(orgId: String, collectionId: String) -> Endpoint<CollectionDetailDTO> {
        Endpoint(method: .get, path: "/orgs/\(orgId)/collections/\(collectionId)")
    }
}
