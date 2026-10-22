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

enum RequestRole: String, Sendable {
    case incoming, outgoing
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

    /// Requests addressed to me that are still open (Home's "Requests for you").
    static func incomingRequests() -> Endpoint<RequestListDTO> {
        requests(role: .incoming, pendingOnly: true)
    }

    static func organisations() -> Endpoint<OrgListDTO> {
        Endpoint(method: .get, path: "/orgs")
    }

    static func collection(orgId: String, collectionId: String) -> Endpoint<CollectionDetailDTO> {
        Endpoint(method: .get, path: "/orgs/\(orgId)/collections/\(collectionId)")
    }

    // MARK: Phase 1

    static func otpStart(phone: String) -> Endpoint<OtpStartResponseDTO> {
        Endpoint(method: .post, path: "/auth/otp/start", body: OtpStartRequest(phone: phone), requiresAuth: false)
    }

    static func otpVerify(phone: String, code: String) -> Endpoint<OtpVerifyResponseDTO> {
        Endpoint(method: .post, path: "/auth/otp/verify", body: OtpVerifyRequest(phone: phone, code: code), requiresAuth: false)
    }

    static func logout() -> Endpoint<Empty> {
        Endpoint(method: .post, path: "/auth/logout")
    }

    static func updateDisplayName(_ displayName: String) -> Endpoint<UserEnvelopeDTO> {
        Endpoint(method: .put, path: "/me", body: DisplayNameRequest(displayName: displayName))
    }

    static func linkBankAccount(_ request: BankAccountRequest) -> Endpoint<BankAccountLinkResponseDTO> {
        Endpoint(method: .put, path: "/me/bank-account", body: request)
    }

    static func providers() -> Endpoint<ProviderListDTO> {
        Endpoint(method: .get, path: "/providers")
    }

    static func directoryLookup(hashes: [String]) -> Endpoint<DirectoryLookupResponseDTO> {
        Endpoint(method: .post, path: "/directory/lookup", body: DirectoryLookupRequest(hashes: hashes))
    }

    // MARK: Phase 2

    static func createPayment(_ request: CreatePaymentRequest) -> Endpoint<PaymentCreateResponseDTO> {
        Endpoint(method: .post, path: "/payments", body: request)
    }

    // MARK: Phase 3

    /// Paying a request: the server takes the payee, amount and reference from the request.
    static func payRequest(_ body: PayRequestBody) -> Endpoint<PaymentCreateResponseDTO> {
        Endpoint(method: .post, path: "/payments", body: body)
    }

    /// `splitId` narrows the list to one split, which is how a split link finds the viewer's own request.
    static func requests(role: RequestRole, pendingOnly: Bool = false, splitId: String? = nil) -> Endpoint<RequestListDTO> {
        var query = [URLQueryItem(name: "role", value: role.rawValue), URLQueryItem(name: "status", value: pendingOnly ? "pending" : "all")]
        if let splitId {
            query.append(URLQueryItem(name: "splitId", value: splitId))
        }
        return Endpoint(method: .get, path: "/requests", query: query)
    }

    static func request(id: String) -> Endpoint<PaymentRequestDTO> {
        Endpoint(method: .get, path: "/requests/\(id)")
    }

    static func declineRequest(id: String) -> Endpoint<PaymentRequestDTO> {
        Endpoint(method: .post, path: "/requests/\(id)/decline")
    }

    static func remindRequest(id: String) -> Endpoint<PaymentRequestDTO> {
        Endpoint(method: .post, path: "/requests/\(id)/remind")
    }

    static func createSplit(_ body: CreateSplitRequest) -> Endpoint<SplitDTO> {
        Endpoint(method: .post, path: "/splits", body: body)
    }

    static func splits() -> Endpoint<SplitListDTO> {
        Endpoint(method: .get, path: "/splits")
    }

    static func split(id: String) -> Endpoint<SplitDTO> {
        Endpoint(method: .get, path: "/splits/\(id)")
    }

    /// "Remind everyone unpaid", or only the requests named.
    static func remindSplit(id: String, requestIds: [String]? = nil) -> Endpoint<SplitReminderResultDTO> {
        Endpoint(method: .post, path: "/splits/\(id)/remind", body: RemindSplitRequest(requestIds: requestIds))
    }

    static func invite() -> Endpoint<InviteDTO> {
        Endpoint(method: .get, path: "/me/invite")
    }
}

// MARK: - Request bodies

struct OtpStartRequest: Codable, Sendable {
    let phone: String
}

struct OtpVerifyRequest: Codable, Sendable {
    let phone: String
    let code: String
}

struct DisplayNameRequest: Codable, Sendable {
    let displayName: String
}

struct CreatePaymentRequest: Codable, Equatable, Sendable {
    let payeeUserId: String
    let amountMinor: Int
    let reference: String
}

struct PayRequestBody: Codable, Equatable, Sendable {
    let requestId: String
    /// Sent so the server can refuse if the request changed under us; it must equal the request's amount.
    let amountMinor: Int
}

struct CreateSplitRequest: Codable, Equatable, Sendable {
    struct Share: Codable, Equatable, Sendable {
        let userId: String
        let amountMinor: Int
    }

    let title: String
    /// The whole bill. Whatever the shares don't cover is the creator's own part.
    let totalMinor: Int
    let shares: [Share]
}

struct RemindSplitRequest: Codable, Sendable {
    let requestIds: [String]?
}

struct BankAccountRequest: Codable, Equatable, Sendable {
    let sortCode: String
    let accountNumber: String
    let accountHolderName: String
    let providerId: String?
}

struct DirectoryLookupRequest: Codable, Sendable {
    let hashes: [String]
}
