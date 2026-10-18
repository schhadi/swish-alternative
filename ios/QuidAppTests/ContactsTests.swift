import XCTest
@testable import QuidApp

final class ContactsTests: XCTestCase {
    func testNormalisationMatchesBackendRules() {
        for input in ["07700 900123", "07700900123", "+447700900123", "+44 7700 900 123", "0044 7700 900123", "447700900123", "(07700) 900-123"] {
            XCTAssertEqual(UKPhone.normalise(input), "+447700900123", input)
        }
        XCTAssertEqual(UKPhone.normalise("01632 96001"), "+44163296001")
        for input in ["+15551234567", "+33123456789", "7700900123", "0", "", "abc", "+44", "+4407700900123", "0770090012345"] {
            XCTAssertNil(UKPhone.normalise(input), input)
        }
    }

    func testDisplayFormatting() {
        XCTAssertEqual(UKPhone.formatForDisplay("+447700900123"), "+44 7700 900123")
        XCTAssertEqual(UKPhone.formatNationalAsTyped("07700900123"), "07700 900123")
        XCTAssertEqual(UKPhone.formatNationalAsTyped("0770"), "0770")
        XCTAssertEqual(UKPhone.formatNationalAsTyped("07700-900123-999"), "07700 900123")
        XCTAssertEqual(UKPhone.masked("+447700900123"), "+44 7700 ***123")
    }

    func testClientHashMatchesSharedVector() {
        // Same vector as backend/test/phoneHash.test.ts
        XCTAssertEqual(PhoneHasher.clientHash("+447700900123"), "a8acc3a90a7b4e4dc65e93db9240ed26523050ef754d63b75b5161de76781436")
        XCTAssertEqual(PhoneHasher.clientHash("+447700900123"), PhoneHasher.clientHash("+447700900123"))
        XCTAssertNotEqual(PhoneHasher.clientHash("+447700900123"), PhoneHasher.clientHash("+447700900124"))
    }

    func testDirectoryLookupBatchesAndMaps() async throws {
        MockServer.shared.reset(latency: 0)
        defer { MockServer.shared.reset() }
        let service = DirectoryService(api: .mock(tokenStore: InMemoryTokenStore(token: MockMode.sessionToken)))

        let contacts = [
            ContactPhone(contactId: "c1", displayName: "Priya P", phoneE164: "+447700900002", hash: PhoneHasher.clientHash("+447700900002")),
            ContactPhone(contactId: "c2", displayName: "Nobody", phoneE164: "+447700900099", hash: PhoneHasher.clientHash("+447700900099")),
            ContactPhone(contactId: "c3", displayName: "Amara O", phoneE164: "+447700900004", hash: PhoneHasher.clientHash("+447700900004")),
        ]
        let matched = try await service.match(contacts)
        XCTAssertEqual(matched.map(\.registeredName), ["Amara Osei", "Priya Patel"])
        XCTAssertEqual(matched.map(\.userId), ["u_amara", "u_priya"])

        let many = (0..<2_300).map { String(format: "%064x", $0) }
        MockServer.shared.reset(latency: 0)
        _ = try await service.lookup(hashes: many)
        let lookups = MockServer.shared.recordedRequests().filter { $0.url?.path(percentEncoded: false) == "/directory/lookup" }
        XCTAssertEqual(lookups.count, 3)
    }

    func testLookupSendsHashesOnlyNeverNumbers() async throws {
        MockServer.shared.reset(latency: 0)
        defer { MockServer.shared.reset() }
        let service = DirectoryService(api: .mock(tokenStore: InMemoryTokenStore(token: MockMode.sessionToken)))
        _ = try await service.lookup(hashes: [PhoneHasher.clientHash("+447700900002")])
        let request = try XCTUnwrap(MockServer.shared.recordedRequests().last)
        let body = try XCTUnwrap(MockURLProtocolTestSupport.body(of: request))
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertFalse(text.contains("+44"))
        XCTAssertTrue(text.contains(PhoneHasher.clientHash("+447700900002")))
    }
}

/// Reads a recorded request body the same way the mock protocol does.
enum MockURLProtocolTestSupport {
    static func body(of request: URLRequest) -> Data? {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: 4096)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
