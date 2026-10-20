import Foundation

// Wire types for the Quid backend (docs/SPEC.md section 5). Field names match the JSON exactly.
// Bank details never appear here: the server returns a bank name and verification status only.

struct UserDTO: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let phoneE164: String?
    let displayName: String
    let createdAt: Date?
}

enum CopStatus: String, Codable, Sendable {
    case match = "MATCH"
    case closeMatch = "CLOSE_MATCH"
    case noMatch = "NO_MATCH"
    case unchecked = "UNCHECKED"
}

struct BankAccountSummaryDTO: Codable, Hashable, Sendable {
    let bankName: String
    let providerId: String?
    let copStatus: CopStatus
    let verifiedAt: Date?
    /// Set while the 24h cooling-off after a bank change is running.
    let coolingOffUntil: Date?
}

struct LimitsDTO: Codable, Hashable, Sendable {
    let perPaymentMinor: Int
    let rolling24hMinor: Int
    let rolling30dMinor: Int
}

struct MeDTO: Codable, Hashable, Sendable {
    let user: UserDTO
    let bankAccount: BankAccountSummaryDTO?
    let limits: LimitsDTO
}

enum PaymentStatus: String, Codable, CaseIterable, Sendable {
    case created = "CREATED"
    case authorizing = "AUTHORIZING"
    case authorized = "AUTHORIZED"
    case executed = "EXECUTED"
    case settled = "SETTLED"
    case failed = "FAILED"
    case cancelled = "CANCELLED"
}

/// The other party as the server wants it shown: a person, or a collection's organisation.
struct CounterpartyDTO: Codable, Hashable, Sendable {
    let userId: String?
    let displayName: String
}

struct PaymentDTO: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let payerUserId: String?
    let payeeUserId: String?
    let collectionId: String?
    let requestId: String?
    let amountMinor: Int
    let currency: String
    let reference: String
    let status: PaymentStatus
    let failureReason: String?
    let createdAt: Date
    let updatedAt: Date
    let settledAt: Date?
    let counterparty: CounterpartyDTO
    /// The payer's bank, when known ("Monzo").
    let bankName: String?
}

struct PaymentListDTO: Codable, Sendable {
    let payments: [PaymentDTO]
}

enum RequestStatus: String, Codable, Sendable {
    case pending = "PENDING"
    case paid = "PAID"
    case declined = "DECLINED"
    case expired = "EXPIRED"
}

struct PaymentRequestDTO: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let requesterUserId: String
    let payerUserId: String
    let amountMinor: Int
    let reference: String
    let note: String?
    let status: RequestStatus
    let paymentId: String?
    let expiresAt: Date
    let createdAt: Date
    let requester: CounterpartyDTO
    /// Present when the request is one share of a split.
    let splitTitle: String?
}

struct RequestListDTO: Codable, Sendable {
    let requests: [PaymentRequestDTO]
}

enum OrgKind: String, Codable, Sendable {
    case society = "SOCIETY"
    case club = "CLUB"
    case flat = "FLAT"
    case other = "OTHER"
}

enum OrgRole: String, Codable, Sendable {
    case treasurer = "TREASURER"
    case member = "MEMBER"
}

enum CollectionStatus: String, Codable, Sendable {
    case open = "OPEN"
    case closed = "CLOSED"
}

struct CollectionSummaryDTO: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let orgId: String
    let title: String
    let amountPerPersonMinor: Int
    let dueAt: Date?
    let slug: String
    let status: CollectionStatus
    let memberCount: Int
    let paidCount: Int
}

struct OrganisationDTO: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let kind: OrgKind
    let role: OrgRole
    let collections: [CollectionSummaryDTO]
}

struct OrgListDTO: Codable, Sendable {
    let organisations: [OrganisationDTO]
}

enum MemberStatus: String, Codable, Sendable {
    case unpaid = "UNPAID"
    case paid = "PAID"
}

struct CollectionMemberDTO: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let status: MemberStatus
    let paidAt: Date?
    let remindCount: Int
}

struct CollectionDetailDTO: Codable, Hashable, Sendable {
    let collection: CollectionSummaryDTO
    let organisationName: String
    let members: [CollectionMemberDTO]
}

struct HealthDTO: Codable, Sendable {
    let status: String
    let service: String
    let version: String
}

struct ErrorDetailsDTO: Codable, Sendable {
    let attemptsRemaining: Int?
}

struct ErrorBodyDTO: Codable, Sendable {
    let error: String
    let message: String?
    let details: ErrorDetailsDTO?
}

// MARK: - Phase 1: auth, onboarding, directory

struct OtpStartResponseDTO: Codable, Sendable {
    let phoneE164: String
    let expiresInSeconds: Int
}

struct OtpVerifyResponseDTO: Codable, Sendable {
    let token: String
    let user: UserDTO
    let isNew: Bool
}

struct UserEnvelopeDTO: Codable, Sendable {
    let user: UserDTO
}

/// Result of PUT /me/bank-account. Only MATCH carries a stored account.
struct BankAccountLinkResponseDTO: Codable, Sendable {
    let copStatus: CopStatus
    let suggestedAccountHolderName: String?
    let bankAccount: BankAccountSummaryDTO?
}

struct ProviderDTO: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let logoUrl: String?
}

struct ProviderListDTO: Codable, Sendable {
    let providers: [ProviderDTO]
}

struct RegisteredContactDTO: Codable, Hashable, Sendable {
    let hash: String
    let userId: String
    let displayName: String
    let firstInitials: String
    /// The bank they receive into, when linked. Never account identifiers.
    let bankName: String?
    /// False until they have a verified account that is not in its cooling-off window.
    let canReceive: Bool
    let coolingOffUntil: Date?
}

/// Who is being paid, as the server confirmed it with their bank. Returned by POST /payments only.
struct PayeeDTO: Codable, Hashable, Sendable {
    let userId: String
    let displayName: String
    /// The name their bank holds; present only for a first-time payee, for the warning sheet.
    let accountHolderName: String?
    let copStatus: CopStatus
    let bankName: String
}

struct PaymentCreateResponseDTO: Codable, Hashable, Sendable {
    let paymentId: String
    let tlPaymentId: String?
    let resourceToken: String
    let authorisationUrl: String?
    let firstTimePayee: Bool
    /// "truelayer" (SDK or hosted page), "fake" (the backend's dev approval page), "mock" (MockMode).
    let provider: String?
    let payee: PayeeDTO
    let payment: PaymentDTO
}

struct DirectoryLookupResponseDTO: Codable, Sendable {
    let registered: [RegisteredContactDTO]
}
