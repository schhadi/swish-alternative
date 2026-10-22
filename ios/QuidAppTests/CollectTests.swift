import CoreImage
import XCTest
@testable import QuidApp

@MainActor
final class CollectTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "CollectTests")!
        defaults.removePersistentDomain(forName: "CollectTests")
    }

    override func tearDown() {
        MockServer.shared.reset()
        super.tearDown()
    }

    private func environment() async -> AppEnvironment {
        let environment = AppEnvironment.demo(signedIn: true, defaults: defaults)
        MockServer.shared.latency = 0
        await environment.loadProfile()
        return environment
    }

    private func lastBody<T: Decodable>(_ type: T.Type, path: String) -> T? {
        MockServer.shared.recordedCalls().last { $0.path == path && $0.method == "POST" }?.decode(type)
    }

    private func hockeyClub(_ environment: AppEnvironment) async throws -> OrganisationDTO {
        let organisations = try await environment.api.send(API.organisations()).organisations
        return try XCTUnwrap(organisations.first { $0.id == "org_hockey" })
    }

    // MARK: - Organisations

    func testSettingUpAnOrganisationFollowsTheBanksAnswer() async {
        let environment = await environment()
        let viewModel = CreateOrganisationViewModel(api: environment.api)
        viewModel.name = "SOAS Netball"
        viewModel.kind = .club
        viewModel.sortCode = "20-00-00"
        viewModel.accountNumber = "1234 5678"
        viewModel.accountHolderName = "soas netball"
        XCTAssertEqual(viewModel.formattedSortCode, "20-00-00")
        XCTAssertTrue(viewModel.isValid)

        await viewModel.submit()
        XCTAssertEqual(viewModel.result?.copStatus, .closeMatch)
        XCTAssertEqual(viewModel.result?.suggestedAccountHolderName, "Soas Netball")
        XCTAssertNil(viewModel.created)

        await viewModel.acceptSuggestedName()
        XCTAssertEqual(lastBody(CreateOrganisationRequest.self, path: "/orgs")?.bankAccount.accountHolderName, "Soas Netball")
        XCTAssertEqual(viewModel.created?.name, "SOAS Netball")
        XCTAssertEqual(viewModel.created?.role, .treasurer)
        XCTAssertNil(viewModel.result)

        let refused = CreateOrganisationViewModel(api: environment.api)
        refused.name = "Flat 2"
        refused.sortCode = "999999"
        refused.accountNumber = "12345678"
        refused.accountHolderName = "Someone Else"
        await refused.submit()
        XCTAssertEqual(refused.result?.copStatus, .noMatch)
        XCTAssertNil(refused.created)
    }

    // MARK: - Creating a collection

    func testCreatingACollectionSendsPeopleOnQuidAndNames() async throws {
        let environment = await environment()
        let viewModel = CreateCollectionViewModel(environment: environment, organisation: try await hockeyClub(environment))
        XCTAssertFalse(viewModel.canSubmit)
        viewModel.title = "  Kit deposit "
        viewModel.setAmountText("25.509")
        XCTAssertEqual(viewModel.amountText, "25.50")
        viewModel.toggle(RegisteredContactDTO(hash: "h", userId: "u_priya", displayName: "Priya Patel", firstInitials: "PP", bankName: "Starling", canReceive: true, coolingOffUntil: nil))
        viewModel.newName = "  Jamie   Lee "
        viewModel.addName()
        viewModel.newName = "jamie lee"
        viewModel.addName()
        XCTAssertEqual(viewModel.memberMessage, "jamie lee is already on the list.")
        XCTAssertEqual(viewModel.members.map(\.displayName), ["Priya Patel", "Jamie Lee"])
        XCTAssertEqual(viewModel.target.minor, 5100)
        XCTAssertEqual(viewModel.submitTitle, "Create · £25.50 each")
        XCTAssertTrue(viewModel.canSubmit)

        await viewModel.submit()
        let body = try XCTUnwrap(lastBody(CreateCollectionRequest.self, path: "/orgs/org_hockey/collections"))
        XCTAssertEqual(body.title, "Kit deposit")
        XCTAssertEqual(body.amountPerPersonMinor, 2550)
        XCTAssertNotNil(body.dueAt)
        XCTAssertEqual(body.members, [.init(userId: "u_priya", displayName: nil), .init(userId: nil, displayName: "Jamie Lee")])
        let created = try XCTUnwrap(viewModel.created)
        XCTAssertEqual(created.collection.memberCount, 2)
        XCTAssertEqual(created.members.map(\.isOnQuid), [true, false])
        XCTAssertNotNil(created.collection.link)
    }

    func testAnAmountNobodyCouldSendIsCaughtBeforeSending() async throws {
        let environment = await environment()
        let viewModel = CreateCollectionViewModel(environment: environment, organisation: try await hockeyClub(environment))
        viewModel.title = "Tour"
        viewModel.setAmountText("300")
        XCTAssertEqual(viewModel.amountProblem, "Each person can pay up to £250, the most anyone can send in one payment.")
        XCTAssertFalse(viewModel.canSubmit)
        viewModel.hasDueDate = false
        viewModel.setAmountText("250")
        XCTAssertTrue(viewModel.canSubmit)
        await viewModel.submit()
        XCTAssertNil(lastBody(CreateCollectionRequest.self, path: "/orgs/org_hockey/collections")?.dueAt)
    }

    // MARK: - Treasurer view

    func testRemindingRespectsTheDailyLimitAndExplainsWhoCantBeReached() async throws {
        let environment = await environment()
        let club = try await hockeyClub(environment)
        let kit = try XCTUnwrap(club.collections.first { $0.id == "col_kit" })
        let viewModel = CollectionDetailViewModel(api: environment.api, collection: kit)
        await viewModel.load()
        XCTAssertEqual(viewModel.memberCount, 15)
        XCTAssertEqual(viewModel.dueReminderCount, 4, "Priya, Tom, Amara and Jonas are on Quid and unpaid")
        let priya = try XCTUnwrap(viewModel.members.first { $0.displayName == "Priya Patel" })
        XCTAssertTrue(viewModel.canRemind(priya))

        await viewModel.remind(priya)
        XCTAssertEqual(viewModel.notice, "Reminded Priya.")
        XCTAssertFalse(viewModel.canRemind(try XCTUnwrap(viewModel.members.first { $0.displayName == "Priya Patel" })))
        XCTAssertEqual(viewModel.dueReminderCount, 3)

        await viewModel.remindAll()
        XCTAssertEqual(viewModel.notice, "Reminded Tom, Amara and Jonas. 8 people aren't on Quid: send them the link.")
        XCTAssertEqual(viewModel.dueReminderCount, 0)
        await viewModel.remindAll()
        XCTAssertEqual(viewModel.notice, "Everyone you can remind was reminded in the last day. 8 people aren't on Quid: send them the link.")
        XCTAssertTrue(viewModel.hasRemindableUnpaid)
    }

    func testClosingStopsRemindersAndTheLink() async throws {
        let environment = await environment()
        let club = try await hockeyClub(environment)
        let trip = try XCTUnwrap(club.collections.first { $0.id == "col_trip" })
        let viewModel = CollectionDetailViewModel(api: environment.api, collection: trip)
        await viewModel.load()
        XCTAssertTrue(viewModel.isOpen)
        XCTAssertEqual(viewModel.linkURL, URL(string: "https://quid.example/c/hockeytr"))
        await viewModel.close()
        XCTAssertFalse(viewModel.isOpen)
        XCTAssertEqual(viewModel.notice, "Collection closed. The link no longer takes payments.")
        XCTAssertEqual(viewModel.dueReminderCount, 0)
        let reloadedClub = try await hockeyClub(environment)
        let reloaded = try XCTUnwrap(reloadedClub.collections.first { $0.id == "col_trip" })
        XCTAssertEqual(reloaded.status, .closed)
    }

    func testTheQRCodeReadsBackAsTheLink() throws {
        let link = "https://quid.example/c/hockeytr"
        let image = try XCTUnwrap(QRCode.image(for: link))
        XCTAssertGreaterThan(image.size.width, 100)
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let features = detector.features(in: try XCTUnwrap(CIImage(image: image)))
        XCTAssertEqual((features.first as? CIQRCodeFeature)?.messageString, link)
    }

    // MARK: - Paying one's share

    func testPayingAShareUsesTheCollectionsAmountAndShowsTheFirstTimeWarning() async throws {
        let environment = await environment()
        let dues = try await environment.api.send(API.collectionsDue()).collections
        let due = try XCTUnwrap(dues.first { $0.isPayable })
        let authoriser = MockPaymentAuthoriser()
        authoriser.delay = 0
        let viewModel = PayViewModel(environment: environment, target: nil, collectionDue: due, authoriser: authoriser)
        viewModel.pollInterval = .milliseconds(20)
        XCTAssertTrue(viewModel.isFixedAmount)
        XCTAssertEqual(viewModel.target?.displayName, "Flat 4B")
        XCTAssertEqual(viewModel.amountMinor, 6240)
        XCTAssertEqual(viewModel.reference, "October bills")
        viewModel.press(.digit(1))
        XCTAssertEqual(viewModel.amountMinor, 6240)

        await viewModel.submit()
        XCTAssertEqual(lastBody(PayCollectionBody.self, path: "/payments"), PayCollectionBody(collectionId: "col_bills", amountMinor: 6240))
        let warning = try XCTUnwrap(viewModel.pendingFirstTime, "first payment to this organisation")
        XCTAssertNil(warning.payee.userId)
        XCTAssertEqual(warning.payee.displayName, "Flat 4B")
        XCTAssertEqual(warning.payee.accountHolderName, "Priya Patel")
        viewModel.acceptFirstTime()
        await viewModel.confirmFirstTime()
        let deadline = Date().addingTimeInterval(6)
        while viewModel.resultKind != .paid, Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(viewModel.resultKind, .paid)
        XCTAssertEqual(viewModel.payment?.counterparty.displayName, "Flat 4B")
        viewModel.stopPolling()

        let home = HomeViewModel(api: environment.api)
        await home.load()
        XCTAssertTrue(home.collectionDues.isEmpty, "paid shares leave Home")
        let again = try await environment.api.send(API.collectionsDue()).collections.first { $0.collectionId == "col_bills" }
        XCTAssertEqual(again?.status, .paid)
    }

    func testAShareWhoseTitleHasNoPlainLettersCanStillBePaid() async {
        let environment = await environment()
        let due = CollectionDueDTO(memberId: "m", collectionId: "c", title: "旅行押金 🎉", organisationName: "Club", amountPerPersonMinor: 1000, dueAt: nil, collectionStatus: .open, status: .unpaid, paidAt: nil, link: "https://quid.example/c/x")
        let viewModel = PayViewModel(environment: environment, target: nil, collectionDue: due)
        XCTAssertEqual(viewModel.reference, "Quid split", "the same fallback the server uses")
        XCTAssertTrue(viewModel.canPay)
    }

    func testReminderSummaryWording() {
        let summary = CollectionSummaryDTO(id: "c", orgId: "o", title: "Trip", amountPerPersonMinor: 3000, dueAt: nil, slug: "s", status: .open, memberCount: 2, paidCount: 0, link: nil)
        let member = { (id: String, name: String) in
            CollectionMemberDTO(id: id, displayName: name, status: .unpaid, paidAt: nil, remindCount: 1, lastRemindedAt: nil, nextReminderAt: nil, isOnQuid: true)
        }
        let detail = CollectionDetailDTO(collection: summary, organisationName: "Club", members: [member("a", "Priya Patel"), member("b", "Jamie Lee")])
        let result = CollectionReminderResultDTO(reminded: ["a"], skipped: [SkippedMemberReminderDTO(memberId: "b", reason: "not_on_quid", nextReminderAt: nil)], detail: detail)
        XCTAssertEqual(CollectionDetailViewModel.summary(of: result), "Reminded Priya. 1 person isn't on Quid: send them the link.")
    }
}
