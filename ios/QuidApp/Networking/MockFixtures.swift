import Foundation

/// Mutable profile the mock backend serves, so the onboarding flow can be exercised end to end without a server.
final class MockProfileState: @unchecked Sendable {
    var displayName = "Sam Okafor"
    var bankLinked = true
    var providerId: String? = "ob-monzo"
    var otpAttemptsRemaining = 5
    var hasSignedIn = true
    /// Payments created through POST /payments this launch, newest last. Their status advances with age.
    var createdPayments: [MockCreatedPayment] = []
    /// Phase 3: splits created this launch (newest last), incoming requests declined, and nudges sent, by request id.
    var createdSplits: [MockSplit] = []
    var declinedRequestIds: Set<String> = []
    var reminders: [String: MockReminder] = [:]
    /// Phase 4: organisations and collections created this launch, member reminders by member id, closed collections.
    var createdOrganisations: [MockOrganisation] = []
    var createdCollections: [MockCollection] = []
    var memberReminders: [String: MockReminder] = [:]
    var closedCollectionIds: Set<String> = []

    /// `complete` = an existing user with name and bank (the demo); otherwise a brand-new user.
    func reset(complete: Bool) {
        displayName = complete ? "Sam Okafor" : ""
        bankLinked = complete
        providerId = complete ? "ob-monzo" : nil
        otpAttemptsRemaining = 5
        hasSignedIn = complete
        createdPayments = []
        createdSplits = []
        declinedRequestIds = []
        reminders = [:]
        createdOrganisations = []
        createdCollections = []
        memberReminders = [:]
        closedCollectionIds = []
    }

    var isComplete: Bool {
        !displayName.isEmpty && bankLinked
    }
}

/// A payment the mock backend created. AUTHORIZING for 2 s, EXECUTED until 4 s, then SETTLED, so the result screen
/// shows Pending turning into Paid.
struct MockCreatedPayment: Sendable {
    let id: String
    let payeeUserId: String
    let payeeName: String
    let amountMinor: Int
    let reference: String
    let createdAt: Date
    /// Set when the payment pays an incoming request.
    var requestId: String? = nil
    /// Set when the payment pays a collection share; the payee is then the organisation.
    var collectionId: String? = nil

    func status(at now: Date = Date()) -> String {
        let age = now.timeIntervalSince(createdAt)
        if age < 2 { return "AUTHORIZING" }
        if age < 4 { return "EXECUTED" }
        return "SETTLED"
    }
}

/// A split the mock backend created. Priya pays her share five seconds after it is created, so the demo shows a
/// split filling up; everyone else stays open until nudged, and nobody declines.
struct MockSplit: Sendable {
    struct Share: Sendable {
        let requestId: String
        let userId: String
        let name: String
        let amountMinor: Int
    }

    let id: String
    let title: String
    let totalMinor: Int
    let createdAt: Date
    let shares: [Share]
}

struct MockReminder: Sendable {
    var at: Date
    var count: Int
}

/// One share of a split with its state worked out, ready to encode.
struct MockShareState: Sendable {
    let requestId: String
    let userId: String
    let name: String
    let amountMinor: Int
    let status: String
    let paidAt: Date?
    let declinedAt: Date?
    let remindedAt: Date?
    let remindCount: Int

    var nextReminderAt: Date? {
        remindedAt?.addingTimeInterval(24 * 3600)
    }

    func canBeReminded(at now: Date) -> Bool {
        status == "PENDING" && (nextReminderAt.map { $0 <= now } ?? true)
    }
}

struct MockOrganisation: Sendable {
    let id: String
    let name: String
    let kind: String
    let bankName: String
}

/// A collection the demo user looks after. In one created this launch, anyone called Priya Patel pays five seconds
/// after it is created, so the treasurer view shows someone flipping to Paid.
struct MockCollection: Sendable {
    struct Member: Sendable {
        let id: String
        let name: String
        let isOnQuid: Bool
        let paidAt: Date?
        let remindCount: Int
        let remindedAt: Date?
    }

    let id: String
    let orgId: String
    let orgName: String
    let title: String
    let amountMinor: Int
    let dueAt: Date?
    let slug: String
    let status: String
    let createdAt: Date
    let members: [Member]
}

/// A request addressed to the demo user.
struct MockIncomingRequest: Sendable {
    let id: String
    let requesterId: String
    let requesterName: String
    let amountMinor: Int
    let reference: String
    let note: String?
    let splitId: String?
    let splitTitle: String?
    let createdAt: Date
    let expiresAt: Date
    /// Fixed history (already paid); nil means worked out from what happened this launch.
    let fixedStatus: String?
    let paidAt: Date?
}

/// Canned backend responses for MockMode. Dates are relative to now so "Today" / "Yesterday" grouping stays realistic.
/// Realistic placeholder data only — no lorem ipsum.
enum MockFixtures {
    static let meUserId = "u_me"
    static let state = MockProfileState()

    static func defaultRoutes() -> [String: MockResponse] {
        [
            "GET /health": .json(#"{"status":"ok","service":"quid-backend","version":"0.1.0"}"#),
            "DELETE /me": .empty(),
            "POST /auth/logout": .empty(),
            "GET /payments/p_1001": .json(sentPayments[0]),
            "GET /providers": .json(providers()),
        ]
    }

    /// Routes that read the request or keep state. They run under the MockServer lock.
    static func defaultHandlers() -> [String: MockHandler] {
        [
            "GET /me": { _ in .json(me()) },
            "GET /payments": { request in
                guard state.hasSignedIn, state.isComplete else { return .json(payments([])) }
                let created = state.createdPayments.reversed().map(createdPaymentJSON)
                if request.query?.contains("role=received") == true { return .json(payments(receivedPayments)) }
                if request.query?.contains("role=sent") == true { return .json(payments(created + sentPayments)) }
                return .json(payments(created + sentPayments + receivedPayments))
            },
            "GET /payments/*": { request in
                let id = String(request.path.dropFirst("/payments/".count))
                if let created = state.createdPayments.first(where: { $0.id == id }) {
                    return .json(createdPaymentJSON(created))
                }
                if let fixture = (sentPayments + receivedPayments).first(where: { $0.contains("\"id\": \"\(id)\"") }) {
                    return .json(fixture)
                }
                return .json(#"{"error":"not_found","message":"We couldn't find that payment."}"#, status: 404)
            },
            "POST /payments": { request in
                if let pay = request.decode(PayRequestBody.self) {
                    return payIncomingRequest(pay)
                }
                if let pay = request.decode(PayCollectionBody.self) {
                    return payCollectionDue(pay)
                }
                guard let body = request.decode(CreatePaymentRequest.self) else {
                    return .json(#"{"error":"validation_error","message":"Request failed validation"}"#, status: 400)
                }
                if body.payeeUserId == meUserId {
                    return .json(#"{"error":"self_payment","message":"You can't pay yourself."}"#, status: 400)
                }
                guard let person = people[body.payeeUserId] else {
                    return .json(#"{"error":"payee_not_found","message":"We couldn't find that person on Quid."}"#, status: 404)
                }
                guard person.bankName != nil else {
                    return .json(#"{"error":"payee_not_payable","message":"\(person.name) hasn't linked a verified bank account yet, so they can't be paid."}"#, status: 400)
                }
                if body.amountMinor > 25000 {
                    return .json(#"{"error":"limit_per_payment","message":"The most you can send in one payment is £250.","details":{"limitMinor":25000,"remainingMinor":25000}}"#, status: 400)
                }
                let reference = body.reference.trimmingCharacters(in: .whitespaces)
                guard !reference.isEmpty, reference.count <= 18 else {
                    return .json(#"{"error":"invalid_reference","message":"Use up to 18 letters, numbers, spaces or & . / -"}"#, status: 400)
                }
                let paidBefore = state.createdPayments.contains { $0.payeeUserId == body.payeeUserId && $0.status() != "AUTHORIZING" }
                    || completedFixturePayees.contains(body.payeeUserId)
                let created = MockCreatedPayment(
                    id: "p_m\(state.createdPayments.count + 1)",
                    payeeUserId: body.payeeUserId,
                    payeeName: person.name,
                    amountMinor: body.amountMinor,
                    reference: reference,
                    createdAt: Date()
                )
                state.createdPayments.append(created)
                return createdPaymentResponse(created, person: person, paidBefore: paidBefore)
            },
            "GET /requests": { request in
                guard state.isComplete else { return .json(#"{"requests":[]}"#) }
                let pendingOnly = request.query?.contains("status=pending") == true
                if request.query?.contains("role=outgoing") == true {
                    let rows = allSplits().flatMap { split in split.shares.map { outgoingRequestJSON($0, split: split) } }
                    return .json(#"{"requests":[\#(rows.joined(separator: ","))]}"#)
                }
                let splitId = URLComponents(string: "?" + (request.query ?? ""))?.queryItems?.first(where: { $0.name == "splitId" })?.value
                let rows = incomingFixtures
                    .filter { !pendingOnly || incomingStatus($0) == "PENDING" }
                    .filter { splitId == nil || $0.splitId == splitId }
                    .map(incomingRequestJSON)
                return .json(#"{"requests":[\#(rows.joined(separator: ","))]}"#)
            },
            "GET /requests/*": { request in
                let id = String(request.path.dropFirst("/requests/".count))
                guard let incoming = incomingFixtures.first(where: { $0.id == id }) else { return requestNotFound }
                return .json(incomingRequestJSON(incoming))
            },
            "POST /requests/*": { request in
                let parts = request.path.split(separator: "/").map(String.init)
                guard parts.count == 3 else { return requestNotFound }
                let id = parts[1]
                switch parts[2] {
                case "decline":
                    guard let incoming = incomingFixtures.first(where: { $0.id == id }) else { return requestNotFound }
                    let status = incomingStatus(incoming)
                    guard status == "PENDING" else { return notPending(status) }
                    state.declinedRequestIds.insert(id)
                    return .json(incomingRequestJSON(incoming))
                case "remind":
                    guard let found = findShare(requestId: id) else { return requestNotFound }
                    let (split, share) = found
                    if share.status != "PENDING" { return notPending(share.status) }
                    if let next = share.nextReminderAt, next > Date() {
                        return .json(#"{"error":"remind_too_soon","message":"You've nudged them in the last day. You can nudge again tomorrow.","details":{"nextReminderAt":"\#(ISO8601.string(from: next))"}}"#, status: 429)
                    }
                    remind(id)
                    let updated = findShare(requestId: id)?.1 ?? share
                    return .json(outgoingRequestJSON(updated, split: split))
                default:
                    return requestNotFound
                }
            },
            "POST /splits": { request in
                guard let body = request.decode(CreateSplitRequest.self) else {
                    return .json(#"{"error":"validation_error","message":"Request failed validation"}"#, status: 400)
                }
                return createSplit(body)
            },
            "GET /splits": { _ in
                guard state.isComplete else { return .json(#"{"splits":[]}"#) }
                return .json(#"{"splits":[\#(allSplits().map(splitJSON).joined(separator: ","))]}"#)
            },
            "GET /splits/*": { request in
                let id = String(request.path.dropFirst("/splits/".count))
                guard let split = allSplits().first(where: { $0.id == id }) else { return splitNotFound }
                return .json(splitJSON(split))
            },
            "POST /splits/*": { request in
                let parts = request.path.split(separator: "/").map(String.init)
                guard parts.count == 3, parts[2] == "remind", let split = allSplits().first(where: { $0.id == parts[1] }) else { return splitNotFound }
                let wanted: Set<String>? = request.decode(RemindSplitRequest.self)?.requestIds.map { Set($0) }
                var reminded: [String] = []
                var skipped: [String] = []
                let now = Date()
                for share in split.shares where wanted?.contains(share.requestId) ?? true {
                    if share.canBeReminded(at: now) {
                        remind(share.requestId)
                        reminded.append("\"\(share.requestId)\"")
                    } else if share.status == "PENDING" {
                        skipped.append(#"{"requestId":"\#(share.requestId)","reason":"too_soon","nextReminderAt":\#(jsonDate(share.nextReminderAt))}"#)
                    } else {
                        skipped.append(#"{"requestId":"\#(share.requestId)","reason":"not_pending","nextReminderAt":null}"#)
                    }
                }
                let updated = allSplits().first { $0.id == split.id } ?? split
                return .json(#"{"reminded":[\#(reminded.joined(separator: ","))],"skipped":[\#(skipped.joined(separator: ","))],"split":\#(splitJSON(updated))}"#)
            },
            "GET /me/invite": { _ in
                .json(#"{"code":"sam2k7qx","url":"https://quid.example/i/sam2k7qx","message":"I'm using Quid to pay friends by phone number. Join me:"}"#)
            },
            "GET /orgs": { _ in .json(state.isComplete ? organisations() : #"{"organisations":[]}"#) },
            "POST /orgs": { request in
                guard let body = request.decode(CreateOrganisationRequest.self) else {
                    return .json(#"{"error":"validation_error","message":"Request failed validation"}"#, status: 400)
                }
                return createOrganisation(body)
            },
            "POST /orgs/*": { request in
                // POST /orgs/<id>/collections
                let parts = request.path.split(separator: "/").map(String.init)
                guard parts.count == 3, parts[2] == "collections", let body = request.decode(CreateCollectionRequest.self) else {
                    return .json(#"{"error":"validation_error","message":"Request failed validation"}"#, status: 400)
                }
                return createCollection(orgId: parts[1], body)
            },
            "GET /orgs/*": { request in
                // GET /orgs/<id>/collections/<cid>
                let parts = request.path.split(separator: "/").map(String.init)
                guard parts.count == 4, let collection = allCollections().first(where: { $0.id == parts[3] && $0.orgId == parts[1] }) else {
                    return collectionNotFound
                }
                return .json(collectionDetailJSON(collection))
            },
            "POST /collections/*": { request in
                let parts = request.path.split(separator: "/").map(String.init)
                guard parts.count == 3, let collection = allCollections().first(where: { $0.id == parts[1] }) else { return collectionNotFound }
                switch parts[2] {
                case "close":
                    state.closedCollectionIds.insert(collection.id)
                    return .json(collectionDetailJSON(allCollections().first { $0.id == collection.id } ?? collection))
                case "remind":
                    guard collection.status == "OPEN" else {
                        return .json(#"{"error":"collection_closed","message":"This collection is closed."}"#, status: 409)
                    }
                    let wanted: Set<String>? = request.decode(RemindCollectionRequest.self)?.memberIds.map { Set($0) }
                    let now = Date()
                    var reminded: [String] = []
                    var skipped: [String] = []
                    for member in collection.members where wanted?.contains(member.id) ?? true {
                        if member.paidAt != nil {
                            if wanted != nil { skipped.append(#"{"memberId":"\#(member.id)","reason":"paid","nextReminderAt":null}"#) }
                        } else if !member.isOnQuid {
                            skipped.append(#"{"memberId":"\#(member.id)","reason":"not_on_quid","nextReminderAt":null}"#)
                        } else if let last = member.remindedAt, last.addingTimeInterval(24 * 3600) > now {
                            skipped.append(#"{"memberId":"\#(member.id)","reason":"too_soon","nextReminderAt":\#(jsonDate(last.addingTimeInterval(24 * 3600)))}"#)
                        } else {
                            state.memberReminders[member.id] = MockReminder(at: now, count: member.remindCount + 1)
                            reminded.append("\"\(member.id)\"")
                        }
                    }
                    let updated = allCollections().first { $0.id == collection.id } ?? collection
                    return .json(#"{"reminded":[\#(reminded.joined(separator: ","))],"skipped":[\#(skipped.joined(separator: ","))],"detail":\#(collectionDetailJSON(updated))}"#)
                default:
                    return collectionNotFound
                }
            },
            "GET /collections/due": { _ in
                guard state.isComplete else { return .json(#"{"collections":[]}"#) }
                return .json(#"{"collections":[\#(collectionDues().joined(separator: ","))]}"#)
            },
            "POST /auth/otp/start": { request in
                guard let body = request.decode(OtpStartRequest.self), let e164 = UKPhone.normalise(body.phone) else {
                    return .json(#"{"error":"invalid_phone","message":"Enter a UK mobile number, like 07700 900123."}"#, status: 400)
                }
                state.otpAttemptsRemaining = 5
                return .json(#"{"phoneE164":"\#(e164)","expiresInSeconds":300}"#)
            },
            "POST /auth/otp/verify": { request in
                guard let body = request.decode(OtpVerifyRequest.self) else {
                    return .json(#"{"error":"validation_error","message":"Request failed validation"}"#, status: 400)
                }
                if body.code == MockMode.otpCode {
                    let isNew = !state.hasSignedIn
                    state.hasSignedIn = true
                    return .json(#"{"token":"\#(MockMode.sessionToken)","user":\#(user()),"isNew":\#(isNew)}"#)
                }
                state.otpAttemptsRemaining = max(0, state.otpAttemptsRemaining - 1)
                if state.otpAttemptsRemaining == 0 {
                    return .json(#"{"error":"otp_locked","message":"Too many attempts. Request a new code.","details":{"attemptsRemaining":0}}"#, status: 429)
                }
                let remaining = state.otpAttemptsRemaining
                let noun = remaining == 1 ? "attempt" : "attempts"
                return .json(#"{"error":"otp_invalid","message":"That code isn't right. \#(remaining) \#(noun) left.","details":{"attemptsRemaining":\#(remaining)}}"#, status: 400)
            },
            "PUT /me": { request in
                guard let body = request.decode(DisplayNameRequest.self) else {
                    return .json(#"{"error":"validation_error","message":"Request failed validation"}"#, status: 400)
                }
                let trimmed = body.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.count >= 2, trimmed.count <= 40 else {
                    return .json(#"{"error":"validation_error","message":"Enter at least 2 characters"}"#, status: 400)
                }
                state.displayName = trimmed
                return .json(#"{"user":\#(user())}"#)
            },
            "PUT /me/bank-account": { request in
                guard let body = request.decode(BankAccountRequest.self) else {
                    return .json(#"{"error":"validation_error","message":"Request failed validation"}"#, status: 400)
                }
                let sortCode = body.sortCode.filter(\.isNumber)
                let name = body.accountHolderName.trimmingCharacters(in: .whitespaces)
                // Fixtures: sort code 999999 -> NO_MATCH; an all-lowercase name -> CLOSE_MATCH with the bank's capitalised version.
                if sortCode == "999999" {
                    return .json(#"{"copStatus":"NO_MATCH"}"#)
                }
                if name == name.lowercased() {
                    return .json(#"{"copStatus":"CLOSE_MATCH","suggestedAccountHolderName":"\#(name.capitalized)"}"#)
                }
                state.bankLinked = true
                state.providerId = body.providerId
                return .json(#"{"copStatus":"MATCH","bankAccount":\#(bankAccount())}"#)
            },
            "POST /directory/lookup": { request in
                guard let body = request.decode(DirectoryLookupRequest.self) else {
                    return .json(#"{"error":"validation_error","message":"Request failed validation"}"#, status: 400)
                }
                let wanted = Set(body.hashes)
                let entries = people.values.sorted { $0.name < $1.name }.compactMap { person -> String? in
                    let hash = PhoneHasher.clientHash(person.phone)
                    guard wanted.contains(hash) else { return nil }
                    let initials = person.name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
                    return #"{"hash":"\#(hash)","userId":"\#(person.userId)","displayName":"\#(person.name)","firstInitials":"\#(initials)","bankName":\#(jsonString(person.bankName)),"canReceive":\#(person.bankName != nil),"coolingOffUntil":null}"#
                }
                return .json(#"{"registered":[\#(entries.joined(separator: ","))]}"#)
            },
        ]
    }

    // MARK: - People

    struct MockPerson: Sendable {
        let userId: String
        let name: String
        let phone: String
        /// nil = no verified bank account, so they cannot be paid (Jonas).
        let bankName: String?
        var accountHolderName: String { name }
    }

    /// Everyone on Quid in the demo, by user id. Phone numbers match MockContactSource.
    static let people: [String: MockPerson] = [
        "u_priya": MockPerson(userId: "u_priya", name: "Priya Patel", phone: "+447700900002", bankName: "Starling"),
        "u_tom": MockPerson(userId: "u_tom", name: "Tom Whitfield", phone: "+447700900003", bankName: "Barclays"),
        "u_amara": MockPerson(userId: "u_amara", name: "Amara Osei", phone: "+447700900004", bankName: "Lloyds"),
        "u_jonas": MockPerson(userId: "u_jonas", name: "Jonas Berg", phone: "+447700900005", bankName: nil),
    ]

    /// Payees with a completed fixture payment, so paying them again is not "first time".
    static let completedFixturePayees: Set<String> = ["u_priya", "u_tom"]

    static func createdPaymentJSON(_ created: MockCreatedPayment) -> String {
        let status = created.status()
        let counterparty = created.collectionId == nil
            ? #"{"userId":"\#(created.payeeUserId)","displayName":"\#(created.payeeName)"}"#
            : #"{"userId":null,"displayName":\#(jsonString(created.payeeName))}"#
        return payment(
            id: created.id,
            payer: meUserId,
            payee: created.collectionId == nil ? created.payeeUserId : nil,
            collectionId: created.collectionId,
            amount: created.amountMinor,
            reference: created.reference,
            status: status,
            created: ISO8601.string(from: created.createdAt),
            settled: status == "SETTLED" ? ISO8601.string(from: created.createdAt.addingTimeInterval(4)) : nil,
            counterparty: counterparty,
            bankName: providerName(state.providerId) ?? "Monzo",
            requestId: created.requestId
        )
    }

    /// The POST /payments answer for a payment the mock backend just created.
    static func createdPaymentResponse(_ created: MockCreatedPayment, person: MockPerson, paidBefore: Bool, payeeIsOrganisation: Bool = false) -> MockResponse {
        let payeeId = payeeIsOrganisation ? "null" : "\"\(person.userId)\""
        let holder = payeeIsOrganisation ? "Priya Patel" : person.accountHolderName
        return .json(
            """
            {
              "paymentId": "\(created.id)",
              "tlPaymentId": "mock_tl_\(created.id)",
              "resourceToken": "mock_token_\(created.id)",
              "authorisationUrl": "https://mock.quid.invalid/authorise/\(created.id)",
              "firstTimePayee": \(!paidBefore),
              "provider": "mock",
              "payee": {"userId": \(payeeId), "displayName": \(jsonString(person.name)), "accountHolderName": \(paidBefore ? "null" : jsonString(holder)), "copStatus": "MATCH", "bankName": "\(person.bankName ?? "")"},
              "payment": \(createdPaymentJSON(created))
            }
            """,
            status: 201
        )
    }

    private static let priya = #"{"userId":"u_priya","displayName":"Priya Patel"}"#
    private static let tom = #"{"userId":"u_tom","displayName":"Tom Whitfield"}"#
    private static let amara = #"{"userId":"u_amara","displayName":"Amara Osei"}"#
    private static let jonas = #"{"userId":"u_jonas","displayName":"Jonas Berg"}"#
    private static let hockeyClub = #"{"userId":null,"displayName":"SOAS Hockey Club"}"#

    // MARK: - /me

    static func user() -> String {
        """
        {"id": "\(meUserId)", "phoneE164": "+447700900001", "displayName": "\(state.displayName)", "createdAt": "\(iso(daysAgo: 40))"}
        """
    }

    static func bankAccount() -> String {
        let bankName = providerName(state.providerId) ?? "Your bank"
        return """
        {"bankName": "\(bankName)", "providerId": \(jsonString(state.providerId)), "copStatus": "MATCH", "verifiedAt": "\(iso(daysAgo: 40))", "coolingOffUntil": null}
        """
    }

    static func me() -> String {
        """
        {
          "user": \(user()),
          "bankAccount": \(state.bankLinked ? bankAccount() : "null"),
          "limits": {
            "perPaymentMinor": 25000,
            "rolling24hMinor": 50000,
            "rolling30dMinor": 200000
          }
        }
        """
    }

    // MARK: - Providers

    static let providerList: [(id: String, name: String)] = [
        ("ob-monzo", "Monzo"), ("ob-starling", "Starling"), ("ob-barclays", "Barclays"), ("ob-lloyds", "Lloyds"),
        ("ob-halifax", "Halifax"), ("ob-natwest", "NatWest"), ("ob-hsbc", "HSBC"), ("ob-santander", "Santander"),
        ("ob-nationwide", "Nationwide"), ("ob-revolut", "Revolut"), ("ob-tsb", "TSB"), ("ob-first-direct", "first direct"),
        ("ob-chase", "Chase"), ("mock-payments-gb-redirect", "Mock Bank (sandbox)"),
    ]

    static func providerName(_ id: String?) -> String? {
        providerList.first { $0.id == id }?.name
    }

    static func providers() -> String {
        let items = providerList.map { #"{"id":"\#($0.id)","displayName":"\#($0.name)","logoUrl":null}"# }
        return #"{"providers":[\#(items.joined(separator: ","))]}"#
    }

    // MARK: - Payments

    static var sentPayments: [String] {
        [
            payment(id: "p_1001", payer: meUserId, payee: "u_priya", amount: 1200, reference: "From Sam", status: "SETTLED", created: iso(hoursAgo: 2), settled: iso(hoursAgo: 2), counterparty: priya),
            payment(id: "p_1002", payer: meUserId, payee: "u_amara", amount: 4500, reference: "Rent share", status: "AUTHORIZING", created: iso(minutesAgo: 20), settled: nil, counterparty: amara),
            payment(id: "p_1003", payer: meUserId, payee: "u_tom", amount: 850, reference: "Lunch", status: "EXECUTED", created: iso(daysAgo: 1, hour: 13), settled: nil, counterparty: tom),
            payment(id: "p_1004", payer: meUserId, payee: nil, collectionId: "col_trip", amount: 3000, reference: "Trip deposit", status: "SETTLED", created: iso(daysAgo: 3, hour: 18), settled: iso(daysAgo: 3, hour: 18), counterparty: hockeyClub),
            payment(id: "p_1005", payer: meUserId, payee: "u_jonas", amount: 2000, reference: "Tickets", status: "FAILED", created: iso(daysAgo: 5, hour: 20), settled: nil, failureReason: "provider_rejected", counterparty: jonas),
        ]
    }

    static var receivedPayments: [String] {
        [
            payment(id: "p_2001", payer: "u_priya", payee: meUserId, amount: 600, reference: "Coffee", status: "SETTLED", created: iso(daysAgo: 1, hour: 9), settled: iso(daysAgo: 1, hour: 9), counterparty: priya, bankName: "Starling"),
            payment(id: "p_2002", payer: "u_tom", payee: meUserId, amount: 1500, reference: "Taxi", status: "SETTLED", created: iso(daysAgo: 6, hour: 23), settled: iso(daysAgo: 6, hour: 23), counterparty: tom, bankName: "Barclays"),
            payment(id: "p_2003", payer: "u_amara", payee: meUserId, amount: 12000, reference: "Deposit back", status: "SETTLED", created: iso(daysAgo: 12, hour: 11), settled: iso(daysAgo: 12, hour: 11), counterparty: amara, bankName: "Lloyds"),
        ]
    }

    static func payments(_ items: [String]) -> String {
        #"{"payments":["# + items.joined(separator: ",") + "]}"
    }

    private static func payment(
        id: String,
        payer: String?,
        payee: String?,
        collectionId: String? = nil,
        amount: Int,
        reference: String,
        status: String,
        created: String,
        settled: String?,
        failureReason: String? = nil,
        counterparty: String,
        bankName: String = "Monzo",
        requestId: String? = nil
    ) -> String {
        """
        {
          "id": "\(id)",
          "payerUserId": \(jsonString(payer)),
          "payeeUserId": \(jsonString(payee)),
          "collectionId": \(jsonString(collectionId)),
          "requestId": \(jsonString(requestId)),
          "amountMinor": \(amount),
          "currency": "GBP",
          "reference": "\(reference)",
          "status": "\(status)",
          "failureReason": \(jsonString(failureReason)),
          "createdAt": "\(created)",
          "updatedAt": "\(settled ?? created)",
          "settledAt": \(jsonString(settled)),
          "counterparty": \(counterparty),
          "bankName": "\(bankName)"
        }
        """
    }

    // MARK: - Requests and splits

    private static let requestNotFound = MockResponse.json(#"{"error":"request_not_found","message":"We couldn't find that request."}"#, status: 404)
    private static let splitNotFound = MockResponse.json(#"{"error":"split_not_found","message":"We couldn't find that split."}"#, status: 404)

    private static func notPending(_ status: String) -> MockResponse {
        let message: String
        switch status {
        case "PAID": message = "This request has already been paid."
        case "DECLINED": message = "This request was declined."
        default: message = "This request has expired."
        }
        return .json(#"{"error":"request_not_pending","message":"\#(message)","details":{"status":"\#(status)"}}"#, status: 409)
    }

    /// Requests addressed to Sam: Priya's pizza split and Tom's Wi-Fi are open; Amara's train tickets were paid.
    static var incomingFixtures: [MockIncomingRequest] {
        let now = Date()
        return [
            MockIncomingRequest(id: "req_301", requesterId: "u_priya", requesterName: "Priya Patel", amountMinor: 1800, reference: "Pizza night", note: "Friday pizza, split four ways", splitId: "split_p1", splitTitle: "Pizza night", createdAt: now.addingTimeInterval(-5 * 3600), expiresAt: now.addingTimeInterval(12 * 86400), fixedStatus: nil, paidAt: nil),
            MockIncomingRequest(id: "req_302", requesterId: "u_tom", requesterName: "Tom Whitfield", amountMinor: 1125, reference: "Flat Wi-Fi", note: nil, splitId: nil, splitTitle: nil, createdAt: now.addingTimeInterval(-2 * 86400), expiresAt: now.addingTimeInterval(9 * 86400), fixedStatus: nil, paidAt: nil),
            MockIncomingRequest(id: "req_299", requesterId: "u_amara", requesterName: "Amara Osei", amountMinor: 2400, reference: "Train tickets", note: "Brighton day trip", splitId: nil, splitTitle: nil, createdAt: now.addingTimeInterval(-6 * 86400), expiresAt: now.addingTimeInterval(8 * 86400), fixedStatus: "PAID", paidAt: now.addingTimeInterval(-5 * 86400)),
        ]
    }

    /// Declined this launch, paid by a payment that left the bank, or still open.
    static func incomingStatus(_ request: MockIncomingRequest) -> String {
        if let fixed = request.fixedStatus { return fixed }
        if state.declinedRequestIds.contains(request.id) { return "DECLINED" }
        if paymentFor(request) != nil { return "PAID" }
        return "PENDING"
    }

    private static func paymentFor(_ request: MockIncomingRequest) -> MockCreatedPayment? {
        state.createdPayments.first { $0.requestId == request.id && $0.status() != "AUTHORIZING" }
    }

    static func incomingRequestJSON(_ request: MockIncomingRequest) -> String {
        let status = incomingStatus(request)
        let payment = paymentFor(request)
        let paidAt = request.paidAt ?? payment?.createdAt.addingTimeInterval(2)
        return """
        {
          "id": "\(request.id)",
          "requesterUserId": "\(request.requesterId)",
          "payerUserId": "\(meUserId)",
          "amountMinor": \(request.amountMinor),
          "reference": "\(request.reference)",
          "note": \(jsonString(request.note)),
          "status": "\(status)",
          "paymentId": \(jsonString(payment?.id)),
          "expiresAt": "\(ISO8601.string(from: request.expiresAt))",
          "createdAt": "\(ISO8601.string(from: request.createdAt))",
          "requester": {"userId":"\(request.requesterId)","displayName":"\(request.requesterName)"},
          "payer": {"userId":"\(meUserId)","displayName":\(jsonString(state.displayName))},
          "splitId": \(jsonString(request.splitId)),
          "splitTitle": \(jsonString(request.splitTitle)),
          "paidAt": \(status == "PAID" ? jsonDate(paidAt) : "null"),
          "declinedAt": \(status == "DECLINED" ? jsonDate(Date()) : "null"),
          "lastRemindedAt": null,
          "remindCount": 0,
          "nextReminderAt": null
        }
        """
    }

    /// POST /payments { requestId }: pays the requester the requested amount, once.
    static func payIncomingRequest(_ body: PayRequestBody) -> MockResponse {
        guard let incoming = incomingFixtures.first(where: { $0.id == body.requestId }) else { return requestNotFound }
        let status = incomingStatus(incoming)
        guard status == "PENDING" else { return notPending(status) }
        guard body.amountMinor == incoming.amountMinor else {
            return .json(#"{"error":"request_amount_mismatch","message":"This request is for \#(Money(minor: incoming.amountMinor).formatted())."}"#, status: 400)
        }
        guard let person = people[incoming.requesterId] else { return requestNotFound }
        let paidBefore = completedFixturePayees.contains(person.userId)
            || state.createdPayments.contains { $0.payeeUserId == person.userId && $0.status() != "AUTHORIZING" }
        let created = MockCreatedPayment(
            id: "p_m\(state.createdPayments.count + 1)",
            payeeUserId: person.userId,
            payeeName: person.name,
            amountMinor: incoming.amountMinor,
            reference: incoming.reference,
            createdAt: Date(),
            requestId: incoming.id
        )
        state.createdPayments.append(created)
        return createdPaymentResponse(created, person: person, paidBefore: paidBefore)
    }

    /// A resolved split: what the app's SplitDTO is built from.
    struct ResolvedSplit {
        let id: String
        let title: String
        let totalMinor: Int
        let createdAt: Date
        let shares: [MockShareState]
    }

    /// Splits Sam created this launch (newest first), then the fixture: Amara declined, Priya paid, Tom is open.
    static func allSplits(now: Date = Date()) -> [ResolvedSplit] {
        let created = state.createdSplits.reversed().map { split in
            ResolvedSplit(
                id: split.id,
                title: split.title,
                totalMinor: split.totalMinor,
                createdAt: split.createdAt,
                shares: split.shares.map { share in
                    let paid = share.userId == "u_priya" && now.timeIntervalSince(split.createdAt) >= 5
                    let reminder = state.reminders[share.requestId]
                    return MockShareState(
                        requestId: share.requestId,
                        userId: share.userId,
                        name: share.name,
                        amountMinor: share.amountMinor,
                        status: paid ? "PAID" : "PENDING",
                        paidAt: paid ? split.createdAt.addingTimeInterval(5) : nil,
                        declinedAt: nil,
                        remindedAt: reminder?.at,
                        remindCount: reminder?.count ?? 0
                    )
                }.sorted { $0.name < $1.name }
            )
        }
        let tomReminder = state.reminders["req_503"] ?? MockReminder(at: now.addingTimeInterval(-30 * 3600), count: 1)
        let fixture = ResolvedSplit(
            id: "split_501",
            title: "Flat cleaning supplies",
            totalMinor: 4800,
            createdAt: now.addingTimeInterval(-2 * 86400),
            shares: [
                MockShareState(requestId: "req_501", userId: "u_amara", name: "Amara Osei", amountMinor: 1200, status: "DECLINED", paidAt: nil, declinedAt: now.addingTimeInterval(-86400), remindedAt: nil, remindCount: 0),
                MockShareState(requestId: "req_502", userId: "u_priya", name: "Priya Patel", amountMinor: 1200, status: "PAID", paidAt: now.addingTimeInterval(-86400), declinedAt: nil, remindedAt: nil, remindCount: 0),
                MockShareState(requestId: "req_503", userId: "u_tom", name: "Tom Whitfield", amountMinor: 1200, status: "PENDING", paidAt: nil, declinedAt: nil, remindedAt: tomReminder.at, remindCount: tomReminder.count),
            ]
        )
        return created + [fixture]
    }

    static func findShare(requestId: String) -> (ResolvedSplit, MockShareState)? {
        for split in allSplits() {
            if let share = split.shares.first(where: { $0.requestId == requestId }) { return (split, share) }
        }
        return nil
    }

    private static func remind(_ requestId: String) {
        let previous = state.reminders[requestId]?.count ?? (requestId == "req_503" ? 1 : 0)
        state.reminders[requestId] = MockReminder(at: Date(), count: previous + 1)
    }

    static func createSplit(_ body: CreateSplitRequest) -> MockResponse {
        let title = body.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            return .json(#"{"error":"invalid_title","message":"Give it a title, like \u201CPizza night\u201D."}"#, status: 400)
        }
        guard !body.shares.isEmpty else {
            return .json(#"{"error":"split_no_people","message":"Choose at least one person to ask."}"#, status: 400)
        }
        if body.shares.contains(where: { $0.amountMinor > 25000 }) {
            return .json(#"{"error":"request_over_limit","message":"You can ask each person for up to £250, the most they can send in one payment."}"#, status: 400)
        }
        if body.shares.reduce(0, { $0 + $1.amountMinor }) > body.totalMinor {
            return .json(#"{"error":"split_shares_exceed_total","message":"The shares add up to more than the total."}"#, status: 400)
        }
        let number = state.createdSplits.count + 1
        var shares: [MockSplit.Share] = []
        for (index, share) in body.shares.enumerated() {
            guard let person = people[share.userId] else {
                return .json(#"{"error":"payer_not_found","message":"We couldn't find one of those people on Quid."}"#, status: 404)
            }
            shares.append(MockSplit.Share(requestId: "req_m\(number)_\(index + 1)", userId: person.userId, name: person.name, amountMinor: share.amountMinor))
        }
        let split = MockSplit(id: "split_m\(number)", title: title, totalMinor: body.totalMinor, createdAt: Date(), shares: shares)
        state.createdSplits.append(split)
        guard let resolved = allSplits().first(where: { $0.id == split.id }) else { return splitNotFound }
        return .json(splitJSON(resolved), status: 201)
    }

    static func splitJSON(_ split: ResolvedSplit) -> String {
        let requested = split.shares.reduce(0) { $0 + $1.amountMinor }
        let paid = split.shares.filter { $0.status == "PAID" }
        let pending = split.shares.filter { $0.status == "PENDING" }.count
        let shares = split.shares.map { share in
            """
            {"id":"share_\(share.requestId)","requestId":"\(share.requestId)","userId":"\(share.userId)","displayName":"\(share.name)","amountMinor":\(share.amountMinor),"status":"\(share.status)","paymentId":\(share.status == "PAID" ? "\"p_\(share.requestId)\"" : "null"),"paidAt":\(jsonDate(share.paidAt)),"declinedAt":\(jsonDate(share.declinedAt)),"lastRemindedAt":\(jsonDate(share.remindedAt)),"remindCount":\(share.remindCount),"nextReminderAt":\(jsonDate(share.nextReminderAt))}
            """
        }
        return """
        {
          "id": "\(split.id)",
          "title": \(jsonString(split.title)),
          "totalMinor": \(split.totalMinor),
          "createdAt": "\(ISO8601.string(from: split.createdAt))",
          "creatorShareMinor": \(max(0, split.totalMinor - requested)),
          "requestedMinor": \(requested),
          "paidMinor": \(paid.reduce(0) { $0 + $1.amountMinor }),
          "shareCount": \(split.shares.count),
          "paidCount": \(paid.count),
          "pendingCount": \(pending),
          "isComplete": \(pending == 0),
          "link": "https://quid.example/s/\(split.id)",
          "shares": [\(shares.joined(separator: ","))]
        }
        """
    }

    /// One share as the request Sam sent, for GET /requests?role=outgoing and the nudge answer.
    static func outgoingRequestJSON(_ share: MockShareState, split: ResolvedSplit) -> String {
        """
        {
          "id": "\(share.requestId)",
          "requesterUserId": "\(meUserId)",
          "payerUserId": "\(share.userId)",
          "amountMinor": \(share.amountMinor),
          "reference": \(jsonString(String(split.title.prefix(18)))),
          "note": null,
          "status": "\(share.status)",
          "paymentId": null,
          "expiresAt": "\(ISO8601.string(from: split.createdAt.addingTimeInterval(14 * 86400)))",
          "createdAt": "\(ISO8601.string(from: split.createdAt))",
          "requester": {"userId":"\(meUserId)","displayName":\(jsonString(state.displayName))},
          "payer": {"userId":"\(share.userId)","displayName":"\(share.name)"},
          "splitId": "\(split.id)",
          "splitTitle": \(jsonString(split.title)),
          "paidAt": \(jsonDate(share.paidAt)),
          "declinedAt": \(jsonDate(share.declinedAt)),
          "lastRemindedAt": \(jsonDate(share.remindedAt)),
          "remindCount": \(share.remindCount),
          "nextReminderAt": \(jsonDate(share.nextReminderAt))
        }
        """
    }

    // MARK: - Collect

    private static let collectionNotFound = MockResponse.json(#"{"error":"collection_not_found","message":"We couldn't find that collection."}"#, status: 404)

    /// SOAS Hockey Club, which Sam looks after: Trip deposit (7 of 12 paid) and Kit order (3 of 15).
    private static func fixtureCollections(now: Date) -> [MockCollection] {
        func member(_ id: String, _ name: String, paidDaysAgo: Int?, reminded: Int = 0) -> MockCollection.Member {
            let onQuid = ["Sam Okafor", "Priya Patel", "Tom Whitfield", "Amara Osei", "Jonas Berg"].contains(name)
            return MockCollection.Member(
                id: id,
                name: name,
                isOnQuid: onQuid,
                paidAt: paidDaysAgo.map { now.addingTimeInterval(-Double($0) * 86400 - 3600) },
                remindCount: reminded,
                remindedAt: reminded > 0 ? now.addingTimeInterval(-30 * 3600) : nil
            )
        }
        let trip = [
            member("m1", "Sam Okafor", paidDaysAgo: 3),
            member("m2", "Priya Patel", paidDaysAgo: 4),
            member("m3", "Tom Whitfield", paidDaysAgo: 2),
            member("m4", "Amara Osei", paidDaysAgo: 1),
            member("m5", "Jonas Berg", paidDaysAgo: 1),
            member("m6", "Leila Haddad", paidDaysAgo: 0),
            member("m7", "Daniel Mensah", paidDaysAgo: 0),
            member("m8", "Chloe Baxter", paidDaysAgo: nil, reminded: 1),
            member("m9", "Yusuf Rahman", paidDaysAgo: nil),
            member("m10", "Hannah Doyle", paidDaysAgo: nil, reminded: 2),
            member("m11", "Marco Ferrante", paidDaysAgo: nil),
            member("m12", "Ines Oliveira", paidDaysAgo: nil, reminded: 1),
        ]
        var kit = [
            member("k1", "Sam Okafor", paidDaysAgo: 1),
            member("k2", "Leila Haddad", paidDaysAgo: 2),
            member("k3", "Daniel Mensah", paidDaysAgo: 2),
        ]
        let unpaid = ["Priya Patel", "Tom Whitfield", "Amara Osei", "Jonas Berg", "Chloe Baxter", "Yusuf Rahman", "Hannah Doyle", "Marco Ferrante", "Ines Oliveira", "Grace Nwosu", "Oliver Hart", "Mei Lin"]
        for (index, name) in unpaid.enumerated() {
            kit.append(member("k\(index + 4)", name, paidDaysAgo: nil))
        }
        return [
            MockCollection(id: "col_trip", orgId: "org_hockey", orgName: "SOAS Hockey Club", title: "Trip deposit", amountMinor: 3000, dueAt: now.addingTimeInterval(6 * 86400), slug: "hockeytr", status: "OPEN", createdAt: now.addingTimeInterval(-5 * 86400), members: trip),
            MockCollection(id: "col_kit", orgId: "org_hockey", orgName: "SOAS Hockey Club", title: "Kit order", amountMinor: 1800, dueAt: now.addingTimeInterval(20 * 86400), slug: "hockeykt", status: "OPEN", createdAt: now.addingTimeInterval(-8 * 86400), members: kit),
        ]
    }

    /// Every collection Sam looks after, newest first, with this launch's reminders, closures and auto-payments applied.
    static func allCollections(now: Date = Date()) -> [MockCollection] {
        let created = state.createdCollections.reversed().map { collection in
            MockCollection(
                id: collection.id, orgId: collection.orgId, orgName: collection.orgName, title: collection.title,
                amountMinor: collection.amountMinor, dueAt: collection.dueAt, slug: collection.slug, status: collection.status,
                createdAt: collection.createdAt,
                members: collection.members.map { member in
                    let paysItself = member.name == "Priya Patel" && now.timeIntervalSince(collection.createdAt) >= 5
                    return MockCollection.Member(
                        id: member.id, name: member.name, isOnQuid: member.isOnQuid,
                        paidAt: paysItself ? collection.createdAt.addingTimeInterval(5) : member.paidAt,
                        remindCount: member.remindCount, remindedAt: member.remindedAt
                    )
                }
            )
        }
        return (created + fixtureCollections(now: now)).map { collection in
            MockCollection(
                id: collection.id, orgId: collection.orgId, orgName: collection.orgName, title: collection.title,
                amountMinor: collection.amountMinor, dueAt: collection.dueAt, slug: collection.slug,
                status: state.closedCollectionIds.contains(collection.id) ? "CLOSED" : collection.status,
                createdAt: collection.createdAt,
                members: collection.members.map { member in
                    guard let reminder = state.memberReminders[member.id] else { return member }
                    return MockCollection.Member(id: member.id, name: member.name, isOnQuid: member.isOnQuid, paidAt: member.paidAt, remindCount: reminder.count, remindedAt: reminder.at)
                }
            )
        }
    }

    private static var allOrganisations: [MockOrganisation] {
        [MockOrganisation(id: "org_hockey", name: "SOAS Hockey Club", kind: "CLUB", bankName: "Monzo")] + state.createdOrganisations
    }

    static func organisations() -> String {
        let collections = allCollections()
        let items = allOrganisations.map { org in
            let summaries = collections.filter { $0.orgId == org.id }.map(collectionSummaryJSON)
            return #"{"id":"\#(org.id)","name":\#(jsonString(org.name)),"kind":"\#(org.kind)","role":"TREASURER","bankName":\#(jsonString(org.bankName)),"collections":[\#(summaries.joined(separator: ","))]}"#
        }
        return #"{"organisations":[\#(items.joined(separator: ","))]}"#
    }

    static func collectionSummaryJSON(_ collection: MockCollection) -> String {
        let paid = collection.members.filter { $0.paidAt != nil }.count
        return """
        {"id":"\(collection.id)","orgId":"\(collection.orgId)","title":\(jsonString(collection.title)),"amountPerPersonMinor":\(collection.amountMinor),"dueAt":\(jsonDate(collection.dueAt)),"slug":"\(collection.slug)","status":"\(collection.status)","memberCount":\(collection.members.count),"paidCount":\(paid),"link":"https://quid.example/c/\(collection.slug)"}
        """
    }

    static func collectionDetailJSON(_ collection: MockCollection) -> String {
        let members = collection.members.map { member in
            #"{"id":"\#(member.id)","displayName":\#(jsonString(member.name)),"status":"\#(member.paidAt == nil ? "UNPAID" : "PAID")","paidAt":\#(jsonDate(member.paidAt)),"remindCount":\#(member.remindCount),"lastRemindedAt":\#(jsonDate(member.remindedAt)),"nextReminderAt":\#(jsonDate(member.remindedAt?.addingTimeInterval(24 * 3600))),"isOnQuid":\#(member.isOnQuid)}"#
        }
        return #"{"collection":\#(collectionSummaryJSON(collection)),"organisationName":\#(jsonString(collection.orgName)),"members":[\#(members.joined(separator: ","))]}"#
    }

    static func createOrganisation(_ body: CreateOrganisationRequest) -> MockResponse {
        let sortCode = body.bankAccount.sortCode.filter(\.isNumber)
        let holder = body.bankAccount.accountHolderName.trimmingCharacters(in: .whitespaces)
        // The same fixtures as linking a personal account: 999999 -> NO_MATCH; an all-lowercase name -> CLOSE_MATCH.
        if sortCode == "999999" {
            return .json(#"{"copStatus":"NO_MATCH"}"#)
        }
        if holder == holder.lowercased() {
            return .json(#"{"copStatus":"CLOSE_MATCH","suggestedAccountHolderName":\#(jsonString(holder.capitalized))}"#)
        }
        let name = body.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return .json(#"{"error":"invalid_name","message":"Enter a name."}"#, status: 400)
        }
        let org = MockOrganisation(id: "org_m\(state.createdOrganisations.count + 1)", name: name, kind: body.kind.rawValue, bankName: providerName(body.bankAccount.providerId) ?? "Their bank")
        state.createdOrganisations.append(org)
        return .json(#"{"copStatus":"MATCH","organisation":{"id":"\#(org.id)","name":\#(jsonString(org.name)),"kind":"\#(org.kind)","role":"TREASURER","bankName":\#(jsonString(org.bankName)),"collections":[]}}"#, status: 201)
    }

    static func createCollection(orgId: String, _ body: CreateCollectionRequest) -> MockResponse {
        guard let org = allOrganisations.first(where: { $0.id == orgId }) else {
            return .json(#"{"error":"organisation_not_found","message":"We couldn't find that organisation."}"#, status: 404)
        }
        let title = body.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            return .json(#"{"error":"invalid_title","message":"Enter a title."}"#, status: 400)
        }
        guard body.amountPerPersonMinor > 0, body.amountPerPersonMinor <= 25000 else {
            return .json(#"{"error":"collection_over_limit","message":"Each person can pay up to £250, the most anyone can send in one payment."}"#, status: 400)
        }
        let number = state.createdCollections.count + 1
        var members: [MockCollection.Member] = []
        for (index, member) in body.members.enumerated() {
            if let userId = member.userId {
                guard let person = people[userId] else {
                    return .json(#"{"error":"member_not_found","message":"We couldn't find one of those people on Quid."}"#, status: 404)
                }
                members.append(MockCollection.Member(id: "cm\(number)_\(index + 1)", name: person.name, isOnQuid: true, paidAt: nil, remindCount: 0, remindedAt: nil))
            } else {
                let name = (member.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else {
                    return .json(#"{"error":"invalid_member_name","message":"Enter each person's name."}"#, status: 400)
                }
                members.append(MockCollection.Member(id: "cm\(number)_\(index + 1)", name: name, isOnQuid: false, paidAt: nil, remindCount: 0, remindedAt: nil))
            }
        }
        let collection = MockCollection(id: "col_m\(number)", orgId: org.id, orgName: org.name, title: title, amountMinor: body.amountPerPersonMinor, dueAt: body.dueAt, slug: "newcol\(number)x", status: "OPEN", createdAt: Date(), members: members)
        state.createdCollections.append(collection)
        guard let resolved = allCollections().first(where: { $0.id == collection.id }) else { return collectionNotFound }
        return .json(collectionDetailJSON(resolved), status: 201)
    }

    /// Collections Sam is on the list of: Flat 4B's October bills (open, unpaid) and the climbing society's term fee (paid).
    private static func dueFixtures(now: Date) -> [(id: String, collectionId: String, title: String, org: String, amount: Int, dueAt: Date?, paidAt: Date?)] {
        [
            (id: "due_bills", collectionId: "col_bills", title: "October bills", org: "Flat 4B", amount: 6240, dueAt: now.addingTimeInterval(2 * 86400), paidAt: nil),
            (id: "due_climb", collectionId: "col_climb", title: "Autumn term membership", org: "SOAS Climbing Society", amount: 1500, dueAt: nil, paidAt: now.addingTimeInterval(-9 * 86400)),
        ]
    }

    private static func duePayment(_ collectionId: String) -> MockCreatedPayment? {
        state.createdPayments.first { $0.collectionId == collectionId && $0.status() != "AUTHORIZING" }
    }

    static func collectionDues(now: Date = Date()) -> [String] {
        dueFixtures(now: now).map { due in
            let paidAt = due.paidAt ?? duePayment(due.collectionId)?.createdAt.addingTimeInterval(2)
            return #"{"memberId":"\#(due.id)","collectionId":"\#(due.collectionId)","title":\#(jsonString(due.title)),"organisationName":\#(jsonString(due.org)),"amountPerPersonMinor":\#(due.amount),"dueAt":\#(jsonDate(due.dueAt)),"collectionStatus":"OPEN","status":"\#(paidAt == nil ? "UNPAID" : "PAID")","paidAt":\#(jsonDate(paidAt)),"link":"https://quid.example/c/\#(due.collectionId)"}"#
        }
    }

    /// POST /payments { collectionId }: Sam pays his share of a collection he is on, once.
    static func payCollectionDue(_ body: PayCollectionBody) -> MockResponse {
        guard let due = dueFixtures(now: Date()).first(where: { $0.collectionId == body.collectionId }) else { return collectionNotFound }
        if due.paidAt != nil || duePayment(due.collectionId) != nil {
            return .json(#"{"error":"already_paid","message":"You've already paid this collection."}"#, status: 409)
        }
        guard body.amountMinor == due.amount else {
            return .json(#"{"error":"collection_amount_mismatch","message":"This collection is \#(Money(minor: due.amount).formatted()) each."}"#, status: 400)
        }
        let created = MockCreatedPayment(
            id: "p_m\(state.createdPayments.count + 1)",
            payeeUserId: "",
            payeeName: due.org,
            amountMinor: due.amount,
            reference: String(due.title.prefix(18)),
            createdAt: Date(),
            collectionId: due.collectionId
        )
        state.createdPayments.append(created)
        // Sam has never paid Flat 4B before, so the bank-held name is shown on the first-time sheet.
        let organisation = MockPerson(userId: "", name: due.org, phone: "", bankName: "Starling")
        return createdPaymentResponse(created, person: organisation, paidBefore: false, payeeIsOrganisation: true)
    }

    // MARK: - Helpers

    /// A JSON string literal (quotes, backslashes and control characters escaped), or null.
    private static func jsonString(_ value: String?) -> String {
        guard let value else { return "null" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(value), let literal = String(data: data, encoding: .utf8) else { return "null" }
        return literal
    }

    private static func jsonDate(_ value: Date?) -> String {
        guard let value else { return "null" }
        return "\"\(ISO8601.string(from: value))\""
    }

    static func iso(minutesAgo: Int) -> String {
        ISO8601.string(from: Date().addingTimeInterval(-Double(minutesAgo) * 60))
    }

    static func iso(hoursAgo: Int) -> String {
        ISO8601.string(from: Date().addingTimeInterval(-Double(hoursAgo) * 3600))
    }

    /// Midday (or the given hour) on the day N days ago. Negative values are days in the future.
    static func iso(daysAgo: Int, hour: Int = 12) -> String {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let dated = calendar.date(bySettingHour: hour, minute: 5, second: 0, of: day) ?? day
        return ISO8601.string(from: dated)
    }
}
