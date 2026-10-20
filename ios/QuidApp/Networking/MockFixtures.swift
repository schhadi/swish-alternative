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

    /// `complete` = an existing user with name and bank (the demo); otherwise a brand-new user.
    func reset(complete: Bool) {
        displayName = complete ? "Sam Okafor" : ""
        bankLinked = complete
        providerId = complete ? "ob-monzo" : nil
        otpAttemptsRemaining = 5
        hasSignedIn = complete
        createdPayments = []
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

    func status(at now: Date = Date()) -> String {
        let age = now.timeIntervalSince(createdAt)
        if age < 2 { return "AUTHORIZING" }
        if age < 4 { return "EXECUTED" }
        return "SETTLED"
    }
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
            "GET /orgs/org_hockey/collections/col_trip": .json(tripCollectionDetail()),
            "GET /orgs/org_hockey/collections/col_kit": .json(kitCollectionDetail()),
            "GET /orgs/org_flat/collections/col_bills": .json(billsCollectionDetail()),
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
                return .json(
                    """
                    {
                      "paymentId": "\(created.id)",
                      "tlPaymentId": "mock_tl_\(created.id)",
                      "resourceToken": "mock_token_\(created.id)",
                      "authorisationUrl": "https://mock.quid.invalid/authorise/\(created.id)",
                      "firstTimePayee": \(!paidBefore),
                      "provider": "mock",
                      "payee": {"userId": "\(body.payeeUserId)", "displayName": "\(person.name)", "accountHolderName": "\(person.accountHolderName)", "copStatus": "MATCH", "bankName": "\(person.bankName ?? "")"},
                      "payment": \(createdPaymentJSON(created))
                    }
                    """,
                    status: 201
                )
            },
            "GET /requests": { _ in .json(state.isComplete ? incomingRequests() : #"{"requests":[]}"#) },
            "GET /orgs": { _ in .json(state.isComplete ? organisations() : #"{"organisations":[]}"#) },
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
        let counterparty = #"{"userId":"\#(created.payeeUserId)","displayName":"\#(created.payeeName)"}"#
        return payment(
            id: created.id,
            payer: meUserId,
            payee: created.payeeUserId,
            amount: created.amountMinor,
            reference: created.reference,
            status: status,
            created: ISO8601.string(from: created.createdAt),
            settled: status == "SETTLED" ? ISO8601.string(from: created.createdAt.addingTimeInterval(4)) : nil,
            counterparty: counterparty,
            bankName: providerName(state.providerId) ?? "Monzo"
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
            payment(id: "p_1005", payer: meUserId, payee: "u_jonas", amount: 2000, reference: "Tickets", status: "FAILED", created: iso(daysAgo: 5, hour: 20), settled: nil, failureReason: "Your bank declined the payment.", counterparty: jonas),
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
        bankName: String = "Monzo"
    ) -> String {
        """
        {
          "id": "\(id)",
          "payerUserId": \(jsonString(payer)),
          "payeeUserId": \(jsonString(payee)),
          "collectionId": \(jsonString(collectionId)),
          "requestId": null,
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

    // MARK: - Requests

    static func incomingRequests() -> String {
        """
        {
          "requests": [
            {
              "id": "req_301",
              "requesterUserId": "u_priya",
              "payerUserId": "\(meUserId)",
              "amountMinor": 1800,
              "reference": "Pizza night",
              "note": "Friday pizza, split four ways",
              "status": "PENDING",
              "paymentId": null,
              "expiresAt": "\(iso(daysAgo: -12))",
              "createdAt": "\(iso(hoursAgo: 5))",
              "requester": \(priya),
              "splitTitle": "Pizza night"
            },
            {
              "id": "req_302",
              "requesterUserId": "u_tom",
              "payerUserId": "\(meUserId)",
              "amountMinor": 1125,
              "reference": "Flat Wi-Fi",
              "note": null,
              "status": "PENDING",
              "paymentId": null,
              "expiresAt": "\(iso(daysAgo: -9))",
              "createdAt": "\(iso(daysAgo: 2, hour: 10))",
              "requester": \(tom),
              "splitTitle": null
            }
          ]
        }
        """
    }

    // MARK: - Collect

    static func organisations() -> String {
        """
        {
          "organisations": [
            {
              "id": "org_hockey",
              "name": "SOAS Hockey Club",
              "kind": "CLUB",
              "role": "TREASURER",
              "collections": [
                \(collectionSummary(id: "col_trip", orgId: "org_hockey", title: "Trip deposit", amount: 3000, dueInDays: 6, slug: "hockey-trip-24", members: 12, paid: 7)),
                \(collectionSummary(id: "col_kit", orgId: "org_hockey", title: "Kit order", amount: 1800, dueInDays: 20, slug: "hockey-kit-aw", members: 15, paid: 3))
              ]
            },
            {
              "id": "org_flat",
              "name": "Flat 4B",
              "kind": "FLAT",
              "role": "MEMBER",
              "collections": [
                \(collectionSummary(id: "col_bills", orgId: "org_flat", title: "October bills", amount: 6240, dueInDays: 2, slug: "flat4b-oct", members: 4, paid: 2))
              ]
            }
          ]
        }
        """
    }

    private static func collectionSummary(id: String, orgId: String, title: String, amount: Int, dueInDays: Int, slug: String, members: Int, paid: Int, status: String = "OPEN") -> String {
        """
        {
          "id": "\(id)",
          "orgId": "\(orgId)",
          "title": "\(title)",
          "amountPerPersonMinor": \(amount),
          "dueAt": "\(iso(daysAgo: -dueInDays, hour: 18))",
          "slug": "\(slug)",
          "status": "\(status)",
          "memberCount": \(members),
          "paidCount": \(paid)
        }
        """
    }

    static func tripCollectionDetail() -> String {
        let members = [
            member("m1", "Sam Okafor", paidDaysAgo: 3),
            member("m2", "Priya Patel", paidDaysAgo: 4),
            member("m3", "Tom Whitfield", paidDaysAgo: 2),
            member("m4", "Amara Osei", paidDaysAgo: 1),
            member("m5", "Jonas Berg", paidDaysAgo: 1),
            member("m6", "Leila Haddad", paidDaysAgo: 0),
            member("m7", "Daniel Mensah", paidDaysAgo: 0),
            member("m8", "Chloe Baxter", paidDaysAgo: nil, reminded: 1),
            member("m9", "Yusuf Rahman", paidDaysAgo: nil, reminded: 0),
            member("m10", "Hannah Doyle", paidDaysAgo: nil, reminded: 2),
            member("m11", "Marco Ferrante", paidDaysAgo: nil, reminded: 0),
            member("m12", "Ines Oliveira", paidDaysAgo: nil, reminded: 1),
        ]
        return collectionDetail(
            summary: collectionSummary(id: "col_trip", orgId: "org_hockey", title: "Trip deposit", amount: 3000, dueInDays: 6, slug: "hockey-trip-24", members: 12, paid: 7),
            organisationName: "SOAS Hockey Club",
            members: members
        )
    }

    static func kitCollectionDetail() -> String {
        var members: [String] = [
            member("k1", "Sam Okafor", paidDaysAgo: 1),
            member("k2", "Leila Haddad", paidDaysAgo: 2),
            member("k3", "Daniel Mensah", paidDaysAgo: 2),
        ]
        let unpaid = ["Priya Patel", "Tom Whitfield", "Amara Osei", "Jonas Berg", "Chloe Baxter", "Yusuf Rahman", "Hannah Doyle", "Marco Ferrante", "Ines Oliveira", "Grace Nwosu", "Oliver Hart", "Mei Lin"]
        for (index, name) in unpaid.enumerated() {
            members.append(member("k\(index + 4)", name, paidDaysAgo: nil, reminded: 0))
        }
        return collectionDetail(
            summary: collectionSummary(id: "col_kit", orgId: "org_hockey", title: "Kit order", amount: 1800, dueInDays: 20, slug: "hockey-kit-aw", members: 15, paid: 3),
            organisationName: "SOAS Hockey Club",
            members: members
        )
    }

    static func billsCollectionDetail() -> String {
        collectionDetail(
            summary: collectionSummary(id: "col_bills", orgId: "org_flat", title: "October bills", amount: 6240, dueInDays: 2, slug: "flat4b-oct", members: 4, paid: 2),
            organisationName: "Flat 4B",
            members: [
                member("b1", "Tom Whitfield", paidDaysAgo: 1),
                member("b2", "Sam Okafor", paidDaysAgo: 0),
                member("b3", "Amara Osei", paidDaysAgo: nil, reminded: 0),
                member("b4", "Jonas Berg", paidDaysAgo: nil, reminded: 1),
            ]
        )
    }

    private static func collectionDetail(summary: String, organisationName: String, members: [String]) -> String {
        """
        {
          "collection": \(summary),
          "organisationName": "\(organisationName)",
          "members": [\(members.joined(separator: ","))]
        }
        """
    }

    private static func member(_ id: String, _ name: String, paidDaysAgo: Int?, reminded: Int = 0) -> String {
        let status = paidDaysAgo == nil ? "UNPAID" : "PAID"
        let paidAt = paidDaysAgo.map { "\"\(iso(daysAgo: $0, hour: 17))\"" } ?? "null"
        return #"{"id":"\#(id)","displayName":"\#(name)","status":"\#(status)","paidAt":\#(paidAt),"remindCount":\#(reminded)}"#
    }

    // MARK: - Helpers

    private static func jsonString(_ value: String?) -> String {
        guard let value else { return "null" }
        return "\"\(value)\""
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
