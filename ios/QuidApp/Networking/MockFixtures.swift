import Foundation

/// Canned backend responses for MockMode. Dates are relative to now so "Today" / "Yesterday" grouping stays realistic.
/// Realistic placeholder data only — no lorem ipsum.
enum MockFixtures {
    static let meUserId = "u_me"

    static func defaultRoutes() -> [String: MockResponse] {
        [
            "GET /health": .json(#"{"status":"ok","service":"quid-backend","version":"0.1.0"}"#),
            "GET /me": .json(me()),
            "DELETE /me": .empty(),
            "GET /payments?role=sent&limit=50": .json(payments(sentPayments)),
            "GET /payments?role=received&limit=50": .json(payments(receivedPayments)),
            "GET /payments": .json(payments(sentPayments + receivedPayments)),
            "GET /payments/p_1001": .json(sentPayments[0]),
            "GET /requests?role=incoming": .json(incomingRequests()),
            "GET /requests": .json(incomingRequests()),
            "GET /orgs": .json(organisations()),
            "GET /orgs/org_hockey/collections/col_trip": .json(tripCollectionDetail()),
            "GET /orgs/org_hockey/collections/col_kit": .json(kitCollectionDetail()),
            "GET /orgs/org_flat/collections/col_bills": .json(billsCollectionDetail()),
        ]
    }

    // MARK: - People

    private static let priya = #"{"userId":"u_priya","displayName":"Priya Patel"}"#
    private static let tom = #"{"userId":"u_tom","displayName":"Tom Whitfield"}"#
    private static let amara = #"{"userId":"u_amara","displayName":"Amara Osei"}"#
    private static let jonas = #"{"userId":"u_jonas","displayName":"Jonas Berg"}"#
    private static let hockeyClub = #"{"userId":null,"displayName":"SOAS Hockey Club"}"#

    // MARK: - /me

    static func me() -> String {
        """
        {
          "user": {
            "id": "\(meUserId)",
            "phoneE164": "+447700900001",
            "displayName": "Sam Okafor",
            "createdAt": "\(iso(daysAgo: 40))"
          },
          "bankAccount": {
            "bankName": "Monzo",
            "providerId": "ob-monzo",
            "copStatus": "MATCH",
            "verifiedAt": "\(iso(daysAgo: 40))",
            "coolingOffUntil": null
          },
          "limits": {
            "perPaymentMinor": 25000,
            "rolling24hMinor": 50000,
            "rolling30dMinor": 200000
          }
        }
        """
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
