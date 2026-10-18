import XCTest
@testable import QuidApp

final class ViewModelTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockServer.shared.reset(latency: 0)
    }

    override func tearDown() {
        MockServer.shared.reset()
        super.tearDown()
    }

    private func mockClient() -> APIClient {
        .mock(tokenStore: InMemoryTokenStore(token: MockMode.sessionToken))
    }

    @MainActor
    func testHomeLoadsEverythingNewestFirst() async {
        let viewModel = HomeViewModel(api: mockClient())
        await viewModel.load()
        XCTAssertNil(viewModel.error)
        XCTAssertEqual(viewModel.me?.user.displayName, "Sam Okafor")
        XCTAssertFalse(viewModel.payments.isEmpty)
        let dates = viewModel.payments.map(\.createdAt)
        XCTAssertEqual(dates, dates.sorted(by: >))
        XCTAssertEqual(viewModel.recentPayments.count, min(5, viewModel.payments.count))
        XCTAssertFalse(viewModel.incomingRequests.isEmpty)
        XCTAssertTrue(viewModel.incomingRequests.allSatisfy { $0.status == .pending })
        XCTAssertFalse(viewModel.isLoading)
    }

    @MainActor
    func testHomeRecentContactsAreUniqueAndExcludeCollections() async {
        let viewModel = HomeViewModel(api: mockClient())
        await viewModel.load()
        let names = viewModel.recentContacts.map(\.displayName)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertFalse(names.contains("SOAS Hockey Club"))
        XCTAssertTrue(viewModel.recentContacts.allSatisfy(\.isRegistered))
        XCTAssertEqual(viewModel.recentContacts.first?.firstName, "Amara")
    }

    @MainActor
    func testCancelledLoadIsNotAnError() async {
        MockServer.shared.reset(latency: 1.0)
        let viewModel = HomeViewModel(api: mockClient())
        let loading = Task { await viewModel.load() }
        try? await Task.sleep(nanoseconds: 100_000_000)
        loading.cancel()
        await loading.value
        XCTAssertNil(viewModel.error)
        XCTAssertNil(viewModel.me)
        XCTAssertFalse(viewModel.isLoading)
    }

    @MainActor
    func testDeleteAccountFailureIsReportedSeparately() async {
        MockServer.shared.register(.delete, "/me", .empty(status: 500))
        let viewModel = MeViewModel(api: mockClient())
        await viewModel.load()
        let deleted = await viewModel.deleteAccount()
        XCTAssertFalse(deleted)
        XCTAssertEqual(viewModel.deleteError, .server(status: 500, message: nil))
        XCTAssertNil(viewModel.error)
        XCTAssertNotNil(viewModel.me)
    }

    @MainActor
    func testHomeSurfacesErrors() async {
        MockServer.shared.register(.get, "/me", .empty(status: 500))
        let viewModel = HomeViewModel(api: mockClient())
        await viewModel.load()
        XCTAssertEqual(viewModel.error, .server(status: 500, message: nil))
        XCTAssertNil(viewModel.me)
    }

    @MainActor
    func testActivityFilterAndSearch() async {
        let viewModel = ActivityViewModel(api: mockClient())
        await viewModel.load()
        let total = viewModel.payments.count
        viewModel.filter = .sent
        let sent = viewModel.filteredPayments.count
        viewModel.filter = .received
        let received = viewModel.filteredPayments.count
        XCTAssertEqual(sent + received, total)
        XCTAssertTrue(viewModel.filteredPayments.allSatisfy { $0.direction(for: viewModel.currentUserId) == .received })
        viewModel.filter = .all
        viewModel.searchText = "priya"
        XCTAssertFalse(viewModel.filteredPayments.isEmpty)
        XCTAssertTrue(viewModel.filteredPayments.allSatisfy { $0.counterparty.displayName.lowercased().contains("priya") })
        viewModel.searchText = "zzz-no-match"
        XCTAssertTrue(viewModel.filteredPayments.isEmpty)
        XCTAssertTrue(viewModel.sections.isEmpty)
    }

    @MainActor
    func testActivitySectionsGroupByDayNewestFirst() async {
        let viewModel = ActivityViewModel(api: mockClient())
        await viewModel.load()
        let sections = viewModel.sections
        let calendar = Calendar.current
        let newest = viewModel.payments.map(\.createdAt).max()
        XCTAssertEqual(sections.first?.id, newest.map { calendar.startOfDay(for: $0) })
        XCTAssertTrue(sections.contains { $0.title == "Yesterday" })
        let days = sections.map(\.id)
        XCTAssertEqual(days, days.sorted(by: >))
        for section in sections {
            XCTAssertTrue(section.payments.allSatisfy { calendar.isDate($0.createdAt, inSameDayAs: section.id) })
        }
    }

    @MainActor
    func testCollectLoadsOrganisationsAndDetail() async {
        let viewModel = CollectViewModel(api: mockClient())
        await viewModel.load()
        XCTAssertEqual(viewModel.organisations.count, 2)
        guard let collection = viewModel.organisations.first?.collections.first else {
            return XCTFail("Expected a collection")
        }
        let detail = CollectionDetailViewModel(api: mockClient(), collection: collection)
        XCTAssertEqual(detail.paidCount, collection.paidCount)
        await detail.load()
        XCTAssertEqual(detail.members.count, collection.memberCount)
        XCTAssertEqual(detail.paidCount, collection.paidCount)
        XCTAssertEqual(detail.collected.minor, collection.paidCount * collection.amountPerPersonMinor)
        XCTAssertEqual(detail.filteredMembers.count, detail.unpaidCount)
        detail.filter = .all
        XCTAssertEqual(detail.filteredMembers.count, detail.memberCount)
    }

    @MainActor
    func testMeDeleteAccountSucceedsInMock() async {
        let viewModel = MeViewModel(api: mockClient())
        await viewModel.load()
        XCTAssertEqual(viewModel.me?.user.phoneE164, "+447700900001")
        let deleted = await viewModel.deleteAccount()
        XCTAssertTrue(deleted)
    }
}
