import XCTest
@testable import QuidApp

final class APIClientTests: XCTestCase {
    private var client: APIClient!

    override func setUp() {
        super.setUp()
        MockServer.shared.reset(latency: 0)
        client = .mock(tokenStore: InMemoryTokenStore(token: "test-token"))
    }

    override func tearDown() {
        MockServer.shared.reset()
        super.tearDown()
    }

    func testDecodesMe() async throws {
        let me = try await client.send(API.me())
        XCTAssertEqual(me.user.displayName, "Sam Okafor")
        XCTAssertEqual(me.bankAccount?.bankName, "Monzo")
        XCTAssertEqual(me.bankAccount?.copStatus, .match)
        XCTAssertEqual(me.limits.perPaymentMinor, 25_000)
    }

    func testDecodesPaymentsWithDates() async throws {
        let sent = try await client.send(API.payments(role: .sent))
        XCTAssertFalse(sent.payments.isEmpty)
        XCTAssertTrue(sent.payments.allSatisfy { $0.payerUserId == MockFixtures.meUserId })
        let received = try await client.send(API.payments(role: .received))
        XCTAssertTrue(received.payments.allSatisfy { $0.payeeUserId == MockFixtures.meUserId })
        XCTAssertNotNil(sent.payments.first(where: { $0.status == .failed })?.failureReason)
    }

    func testSendsBearerTokenAndAcceptHeader() async throws {
        _ = try await client.send(API.me())
        let request = MockServer.shared.recordedRequests().last
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request?.url?.path(percentEncoded: false), "/me")
    }

    func testOmitsTokenWhenNotRequired() async throws {
        _ = try await client.send(API.health())
        let request = MockServer.shared.recordedRequests().last
        XCTAssertNil(request?.value(forHTTPHeaderField: "Authorization"))
    }

    func testEncodesQueryItems() async throws {
        _ = try await client.send(API.payments(role: .received, limit: 50))
        let request = MockServer.shared.recordedRequests().last
        XCTAssertEqual(request?.url?.query(percentEncoded: false), "role=received&limit=50")
    }

    func testMapsUnauthorized() async {
        MockServer.shared.register(.get, "/me", .json(#"{"error":"unauthorized","message":"Session expired"}"#, status: 401))
        await assertThrows(API.me(), expected: .unauthorized)
    }

    func testMapsValidationMessage() async {
        MockServer.shared.register(.get, "/me", .json(#"{"error":"validation_error","message":"Reference too long"}"#, status: 400))
        await assertThrows(API.me(), expected: .validation("Reference too long"))
    }

    func testMapsServerError() async {
        MockServer.shared.register(.get, "/me", .json(#"{"error":"internal_error","message":"Something went wrong"}"#, status: 500))
        await assertThrows(API.me(), expected: .server(status: 500, message: "Something went wrong"))
    }

    func testMapsRateLimited() async {
        MockServer.shared.register(.get, "/me", .empty(status: 429))
        await assertThrows(API.me(), expected: .rateLimited)
        MockServer.shared.register(.get, "/me", .json(#"{"error":"rate_limited","message":"Slow down"}"#, status: 429))
        await assertThrows(API.me(), expected: .rateLimited)
    }

    func testMapsCodedRejections() async {
        MockServer.shared.register(.get, "/me", .json(#"{"error":"otp_invalid","message":"That code isn't right. 2 attempts left.","details":{"attemptsRemaining":2}}"#, status: 400))
        await assertThrows(API.me(), expected: .api(code: "otp_invalid", message: "That code isn't right. 2 attempts left.", details: APIErrorDetails(attemptsRemaining: 2)))
        MockServer.shared.register(.get, "/me", .json(#"{"error":"otp_locked","message":"Too many attempts."}"#, status: 429))
        await assertThrows(API.me(), expected: .api(code: "otp_locked", message: "Too many attempts.", details: APIErrorDetails(attemptsRemaining: nil)))
    }

    func testPostsJSONBodies() async throws {
        let response = try await client.send(API.otpStart(phone: "07700 900001"))
        XCTAssertEqual(response.phoneE164, "+447700900001")
        let request = try XCTUnwrap(MockServer.shared.recordedRequests().last)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testMapsDecodingFailure() async {
        MockServer.shared.register(.get, "/me", .json("{}"))
        await assertThrows(API.me(), expected: .decoding)
    }

    func testUnknownRouteIsNotFound() async {
        await assertThrows(API.payment(id: "does-not-exist"), expected: .notFound)
    }

    func testEmptyResponseDecodesAsEmpty() async throws {
        _ = try await client.send(API.deleteAccount())
        XCTAssertEqual(MockServer.shared.recordedRequests().last?.httpMethod, "DELETE")
    }

    private func assertThrows<Response: Decodable>(_ endpoint: Endpoint<Response>, expected: AppError, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await client.send(endpoint)
            XCTFail("Expected \(expected) but the call succeeded", file: file, line: line)
        } catch let error as AppError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Expected AppError, got \(error)", file: file, line: line)
        }
    }
}
