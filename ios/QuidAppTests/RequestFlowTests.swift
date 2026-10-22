import XCTest
@testable import QuidApp

@MainActor
final class RequestFlowTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "RequestFlowTests")!
        defaults.removePersistentDomain(forName: "RequestFlowTests")
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

    private func contact(_ userId: String, _ name: String) -> RegisteredContactDTO {
        RegisteredContactDTO(hash: "h_\(userId)", userId: userId, displayName: name, firstInitials: "", bankName: nil, canReceive: true, coolingOffUntil: nil)
    }

    private func lastBody<T: Decodable>(_ type: T.Type, path: String) -> T? {
        MockServer.shared.recordedCalls().last { $0.path == path && $0.method == "POST" }?.decode(type)
    }

    // MARK: - Splitting arithmetic

    func testEqualSharesNeverLoseAPenny() {
        XCTAssertEqual(RequestViewModel.equalShares(totalMinor: 6000, people: 2, includeMe: true).each, [2000, 2000])
        XCTAssertEqual(RequestViewModel.equalShares(totalMinor: 6000, people: 2, includeMe: true).mine, 2000)
        XCTAssertEqual(RequestViewModel.equalShares(totalMinor: 1000, people: 3, includeMe: false).each, [334, 333, 333])
        XCTAssertEqual(RequestViewModel.equalShares(totalMinor: 1000, people: 2, includeMe: true).each, [333, 333])
        XCTAssertEqual(RequestViewModel.equalShares(totalMinor: 1000, people: 2, includeMe: true).mine, 334, "the requester absorbs the odd pennies")
        XCTAssertEqual(RequestViewModel.equalShares(totalMinor: 2, people: 3, includeMe: false).each, [1, 1, 0])
        XCTAssertEqual(RequestViewModel.equalShares(totalMinor: 0, people: 2, includeMe: false).each, [0, 0])
        for total in [1, 7, 99, 1000, 4999, 25001] {
            for people in 1...5 {
                for includeMe in [true, false] {
                    let split = RequestViewModel.equalShares(totalMinor: total, people: people, includeMe: includeMe)
                    XCTAssertEqual(split.each.reduce(0, +) + split.mine, total, "\(total) between \(people), includeMe \(includeMe)")
                }
            }
        }
    }

    func testTypedAmountsFollowTheKeypadRules() {
        XCTAssertEqual(PayViewModel.sanitisedAmount("12.509"), "12.50")
        XCTAssertEqual(PayViewModel.sanitisedAmount("£1,5"), "1.5")
        XCTAssertEqual(PayViewModel.sanitisedAmount("1234567"), "12345")
        XCTAssertEqual(PayViewModel.sanitisedAmount("abc"), "")
        XCTAssertEqual(PayViewModel.sanitisedAmount(".5"), "0.5")
    }

    // MARK: - Request flow

    func testPickingPeopleAndSplittingEquallySendsOneSplit() async {
        let viewModel = RequestViewModel(environment: await environment())
        XCTAssertEqual(viewModel.continueTitle, "Choose who to ask")
        viewModel.continueToAmount()
        XCTAssertTrue(viewModel.path.isEmpty, "nobody picked yet")

        viewModel.toggle(contact("u_priya", "Priya Patel"))
        viewModel.toggle(contact("u_tom", "Tom Whitfield"))
        viewModel.toggle(contact("u_amara", "Amara Osei"))
        viewModel.toggle(contact("u_amara", "Amara Osei"))
        XCTAssertEqual(viewModel.people.map(\.userId), ["u_priya", "u_tom"])
        XCTAssertTrue(viewModel.isSelected("u_tom"))
        XCTAssertEqual(viewModel.continueTitle, "Continue with 2 people")
        viewModel.continueToAmount()
        XCTAssertEqual(viewModel.path, [.amount])

        viewModel.press(.digit(6))
        viewModel.press(.digit(0))
        viewModel.includeMe = true
        XCTAssertEqual(viewModel.shareAmounts, [2000, 2000])
        XCTAssertEqual(viewModel.myShareMinor, 2000)
        XCTAssertEqual(viewModel.summaryLine, "£20.00 each from Priya and Tom · your share £20.00")
        XCTAssertEqual(viewModel.submitTitle, "Request £40")
        XCTAssertFalse(viewModel.canSubmit, "a title is required")
        viewModel.title = "  Pizza night "
        XCTAssertTrue(viewModel.canSubmit)

        await viewModel.submit()
        let body = lastBody(CreateSplitRequest.self, path: "/splits")
        XCTAssertEqual(body, CreateSplitRequest(title: "Pizza night", totalMinor: 6000, shares: [.init(userId: "u_priya", amountMinor: 2000), .init(userId: "u_tom", amountMinor: 2000)]))
        guard case .sent(let split)? = viewModel.path.last else {
            return XCTFail("expected the split detail, got \(viewModel.path)")
        }
        XCTAssertEqual(split.title, "Pizza night")
        XCTAssertEqual(split.shareCount, 2)
        XCTAssertEqual(split.paidCount, 0)
        XCTAssertEqual(split.creatorShareMinor, 2000)
        XCTAssertNil(viewModel.error)
    }

    func testCustomAmountsAreWhatEachPersonIsAsked() async {
        let viewModel = RequestViewModel(environment: await environment())
        viewModel.toggle(contact("u_priya", "Priya Patel"))
        viewModel.toggle(contact("u_tom", "Tom Whitfield"))
        viewModel.mode = .custom
        viewModel.title = "Taxi"
        viewModel.setAmountText("12.5", for: "u_priya")
        XCTAssertFalse(viewModel.canSubmit, "Tom has no amount yet")
        viewModel.setAmountText("7.25", for: "u_tom")
        XCTAssertEqual(viewModel.shareAmounts, [1250, 725])
        XCTAssertEqual(viewModel.totalMinor, 1975)
        XCTAssertEqual(viewModel.myShareMinor, 0)
        XCTAssertTrue(viewModel.canSubmit)
        await viewModel.submit()
        XCTAssertEqual(lastBody(CreateSplitRequest.self, path: "/splits")?.totalMinor, 1975)
    }

    func testAmountsNobodyCouldPayAreCaughtBeforeSending() async {
        let viewModel = RequestViewModel(environment: await environment())
        viewModel.toggle(contact("u_priya", "Priya Patel"))
        viewModel.title = "Rent"
        for key in [PayViewModel.KeypadKey.digit(3), .digit(0), .digit(0)] { viewModel.press(key) }
        XCTAssertEqual(viewModel.amountProblem, "You can ask each person for up to £250, the most they can send in one payment.")
        XCTAssertFalse(viewModel.canSubmit)
        viewModel.includeMe = true
        XCTAssertNil(viewModel.amountProblem, "£300 split with me is £150 each")
        XCTAssertTrue(viewModel.canSubmit)
    }

    func testTitlesWithQuotesSurviveTheMockServer() async throws {
        let environment = await environment()
        let split = try await environment.api.send(API.createSplit(CreateSplitRequest(title: #"Dinner at "Luigi's" \ 2"#, totalMinor: 2000, shares: [.init(userId: "u_tom", amountMinor: 1000)])))
        XCTAssertEqual(split.title, #"Dinner at "Luigi's" \ 2"#)
        let list = try await environment.api.send(API.splits())
        XCTAssertTrue(list.splits.contains { $0.id == split.id })
    }

    func testTitleIsCappedAndPrefillComesFromAPayment() async {
        let environment = await environment()
        let viewModel = RequestViewModel(environment: environment, prefill: RequestPrefill(totalMinor: 4500, title: "Concert tickets", includeMe: true))
        XCTAssertEqual(viewModel.totalText, "45")
        XCTAssertEqual(viewModel.title, "Concert tickets")
        XCTAssertTrue(viewModel.includeMe)
        viewModel.title = String(repeating: "x", count: 60)
        XCTAssertEqual(viewModel.title.count, RequestViewModel.titleMaxLength)
    }

    func testServerRefusalShowsInline() async {
        let viewModel = RequestViewModel(environment: await environment())
        MockServer.shared.register(.post, "/splits", .json(#"{"error":"requester_cooling_off","message":"You changed your bank account recently. You can ask for money again from Thu 22 Oct, 14:05."}"#, status: 400))
        viewModel.toggle(contact("u_priya", "Priya Patel"))
        viewModel.setAmountText("5", for: "u_priya")
        viewModel.mode = .custom
        viewModel.setAmountText("5", for: "u_priya")
        viewModel.title = "Lunch"
        await viewModel.submit()
        XCTAssertEqual(viewModel.error?.code, "requester_cooling_off")
        XCTAssertEqual(viewModel.inlineMessage, "You changed your bank account recently. You can ask for money again from Thu 22 Oct, 14:05.")
        XCTAssertTrue(viewModel.path.isEmpty)
    }

    // MARK: - Split detail

    func testNudgingOnePersonThenEveryoneRespectsTheDailyLimit() async throws {
        let environment = await environment()
        let list = try await environment.api.send(API.splits())
        let fixture = try XCTUnwrap(list.splits.first { $0.id == "split_501" })
        XCTAssertEqual(fixture.progressLine, "1 of 3 paid")
        let viewModel = SplitDetailViewModel(api: environment.api, split: fixture)
        let tom = try XCTUnwrap(fixture.shares.first { $0.userId == "u_tom" })
        XCTAssertTrue(tom.canNudge(), "nudged 30 hours ago")
        XCTAssertEqual(viewModel.dueReminderCount, 1)

        await viewModel.nudge(tom)
        XCTAssertEqual(viewModel.notice, "Nudged Tom. You can nudge again tomorrow.")
        let after = try XCTUnwrap(viewModel.split.shares.first { $0.userId == "u_tom" })
        XCTAssertEqual(after.remindCount, 2)
        XCTAssertFalse(after.canNudge())
        XCTAssertEqual(viewModel.dueReminderCount, 0)

        await viewModel.remindAll()
        XCTAssertEqual(viewModel.notice, "Everyone unpaid was nudged in the last day. Try again tomorrow.")
    }

    func testANewSplitFillsUpAsPeoplePay() async throws {
        let environment = await environment()
        let created = try await environment.api.send(API.createSplit(CreateSplitRequest(title: "Brunch", totalMinor: 3000, shares: [.init(userId: "u_priya", amountMinor: 1500)])))
        XCTAssertEqual(created.progressLine, "0 of 1 paid")
        XCTAssertEqual(created.link, "https://quid.example/s/\(created.id)")
        let viewModel = SplitDetailViewModel(api: environment.api, split: created, justCreated: true)
        await viewModel.remindAll()
        XCTAssertEqual(viewModel.notice, "Reminded Priya.")
        // In MockMode Priya pays her share five seconds after the split is created.
        let deadline = Date().addingTimeInterval(8)
        while viewModel.split.paidCount == 0, Date() < deadline {
            try await Task.sleep(nanoseconds: 250_000_000)
            await viewModel.load()
        }
        XCTAssertEqual(viewModel.split.progressLine, "1 of 1 paid")
        XCTAssertTrue(viewModel.split.isComplete)
    }

    func testReminderSummaryNamesWhoWasRemindedAndWhoWasSkipped() throws {
        let split = SplitDTO(
            id: "s", title: "Dinner", totalMinor: 3000, createdAt: Date(), creatorShareMinor: 0, requestedMinor: 3000, paidMinor: 0,
            shareCount: 3, paidCount: 0, pendingCount: 3, isComplete: false, link: "https://quid.example/s/s",
            shares: [
                SplitShareDTO(id: "1", requestId: "r1", userId: "u1", displayName: "Priya Patel", amountMinor: 1000, status: .pending, paymentId: nil, paidAt: nil, declinedAt: nil, lastRemindedAt: nil, remindCount: 1, nextReminderAt: nil),
                SplitShareDTO(id: "2", requestId: "r2", userId: "u2", displayName: "Tom Whitfield", amountMinor: 1000, status: .pending, paymentId: nil, paidAt: nil, declinedAt: nil, lastRemindedAt: nil, remindCount: 1, nextReminderAt: nil),
                SplitShareDTO(id: "3", requestId: "r3", userId: "u3", displayName: "Amara Osei", amountMinor: 1000, status: .pending, paymentId: nil, paidAt: nil, declinedAt: nil, lastRemindedAt: Date(), remindCount: 1, nextReminderAt: Date().addingTimeInterval(3600)),
            ]
        )
        let result = SplitReminderResultDTO(reminded: ["r1", "r2"], skipped: [SkippedReminderDTO(requestId: "r3", reason: "too_soon", nextReminderAt: nil)], split: split)
        XCTAssertEqual(SplitDetailViewModel.summary(of: result, in: split), "Reminded Priya and Tom. 1 person was nudged in the last day.")
    }

    // MARK: - Incoming requests

    func testPayingARequestUsesItsAmountAndReferenceAndClosesIt() async throws {
        let environment = await environment()
        let incoming = try await environment.api.send(API.incomingRequests()).requests
        let pizza = try XCTUnwrap(incoming.first { $0.id == "req_301" })
        let authoriser = MockPaymentAuthoriser()
        authoriser.delay = 0
        let viewModel = PayViewModel(environment: environment, target: nil, request: pizza, authoriser: authoriser)
        viewModel.pollInterval = .milliseconds(20)
        XCTAssertFalse(viewModel.rootIsPicker)
        XCTAssertEqual(viewModel.target?.userId, "u_priya")
        XCTAssertEqual(viewModel.amountMinor, 1800)
        XCTAssertEqual(viewModel.reference, "Pizza night")
        viewModel.press(.digit(9))
        viewModel.setQuickAmount(500)
        XCTAssertEqual(viewModel.amountMinor, 1800, "a request fixes the amount")
        XCTAssertNil(viewModel.splitPrefill)

        await viewModel.submit()
        XCTAssertEqual(lastBody(PayRequestBody.self, path: "/payments"), PayRequestBody(requestId: "req_301", amountMinor: 1800))
        XCTAssertEqual(viewModel.created?.payment.requestId, "req_301")
        let deadline = Date().addingTimeInterval(6)
        while viewModel.resultKind != .paid, Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(viewModel.resultKind, .paid)
        viewModel.stopPolling()
        let open = try await environment.api.send(API.incomingRequests()).requests
        XCTAssertFalse(open.contains { $0.id == "req_301" }, "a paid request leaves Home")
        let all = try await environment.api.send(API.requests(role: .incoming)).requests
        XCTAssertEqual(all.first { $0.id == "req_301" }?.status, .paid)
    }

    func testDecliningFromHomeRemovesTheRequest() async {
        let environment = await environment()
        let home = HomeViewModel(api: environment.api)
        await home.load()
        let tomRequest = home.incomingRequests.first { $0.id == "req_302" }
        XCTAssertNotNil(tomRequest)
        if let tomRequest {
            XCTAssertEqual(IncomingRequestViewModel.declineQuestion(for: tomRequest), "Decline Tom's request for £11.25?")
            await home.decline(tomRequest)
        }
        XCTAssertFalse(home.incomingRequests.contains { $0.id == "req_302" })
        XCTAssertNil(home.requestError)
        await home.load()
        XCTAssertFalse(home.incomingRequests.contains { $0.id == "req_302" }, "declined stays declined")
    }

    func testIncomingRequestDetailDeclinesAndExplainsWhenItCannot() async throws {
        let environment = await environment()
        let all = try await environment.api.send(API.requests(role: .incoming)).requests
        let paid = try XCTUnwrap(all.first { $0.id == "req_299" })
        let paidModel = IncomingRequestViewModel(api: environment.api, request: paid)
        XCTAssertFalse(paidModel.isOpen)
        await paidModel.decline()
        XCTAssertEqual(paidModel.request.status, .paid, "nothing to decline")

        let open = try XCTUnwrap(all.first { $0.id == "req_302" })
        let openModel = IncomingRequestViewModel(api: environment.api, request: open)
        await openModel.decline()
        XCTAssertEqual(openModel.request.status, .declined)
        XCTAssertNil(openModel.error)
    }

    // MARK: - Links and invites

    func testDeepLinksOpenSplitsAndNothingElse() {
        XCTAssertEqual(DeepLink(url: URL(string: "quid://split/2f1c6a4e-0b7d-4a51-9a3e-4c1d2b3a4f5e")!), .split(id: "2f1c6a4e-0b7d-4a51-9a3e-4c1d2b3a4f5e"))
        XCTAssertEqual(DeepLink(url: URL(string: "https://quid.example/s/split_501")!), .split(id: "split_501"))
        XCTAssertNil(DeepLink(url: URL(string: "quid://return/payment")!), "the bank's return goes to the authoriser")
        XCTAssertNil(DeepLink(url: URL(string: "quid://split/")!))
        XCTAssertNil(DeepLink(url: URL(string: "quid://split/a/b")!))
        XCTAssertNil(DeepLink(url: URL(string: "https://quid.example/i/sam2k7qx")!))
        XCTAssertNil(DeepLink(url: URL(string: "quid://split/..%2Fme")!))
        XCTAssertNil(DeepLink(url: URL(string: "https://quid.example/s/" + String(repeating: "a", count: 65))!))
    }

    func testSplitLinkShowsTheCreatorTheirSplitAndAPayerTheirRequest() async {
        let environment = await environment()
        let mine = SplitLinkViewModel(api: environment.api, splitId: "split_501")
        await mine.resolve()
        guard case .mine(let split) = mine.state else { return XCTFail("expected the creator's split, got \(mine.state)") }
        XCTAssertEqual(split.title, "Flat cleaning supplies")

        let theirs = SplitLinkViewModel(api: environment.api, splitId: "split_p1")
        await theirs.resolve()
        guard case .forMe(let request) = theirs.state else { return XCTFail("expected Priya's request, got \(theirs.state)") }
        XCTAssertEqual(request.id, "req_301")

        let stranger = SplitLinkViewModel(api: environment.api, splitId: "split_nobody")
        await stranger.resolve()
        guard case .notFound = stranger.state else { return XCTFail("expected not found, got \(stranger.state)") }
    }

    func testPickerLoadsTheInviteLinkForContactsNotOnQuid() async {
        let environment = await environment()
        let picker = ContactPickerViewModel(contactSource: environment.contactSource, api: environment.api)
        XCTAssertNil(picker.inviteURL)
        await picker.load()
        XCTAssertEqual(picker.inviteURL, URL(string: "https://quid.example/i/sam2k7qx"))
        XCTAssertEqual(picker.invite?.message, "I'm using Quid to pay friends by phone number. Join me:")
    }

    func testNameListsStayShort() {
        XCTAssertEqual(NameList.firstNames(["Priya Patel"]), "Priya")
        XCTAssertEqual(NameList.firstNames(["Priya Patel", "Tom Whitfield"]), "Priya and Tom")
        XCTAssertEqual(NameList.firstNames(["Priya Patel", "Tom Whitfield", "Amara Osei"]), "Priya, Tom and Amara")
        XCTAssertEqual(NameList.firstNames(["A B", "C D", "E F", "G H", "I J"]), "A, C and 3 others")
    }
}
