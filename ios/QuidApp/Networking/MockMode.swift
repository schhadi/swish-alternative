import Foundation

/// MockMode answers every API call in-process so the UI can be built and demoed with no backend.
/// Turn it on with the `-mock` launch argument (the "QuidApp-Mock" scheme does this), `QUID_MOCK=1`, or Xcode previews.
/// Add `-signed-out` to start on the welcome screen with a fresh mock user (used by the onboarding UI test).
enum MockMode {
    static var isEnabled: Bool {
        let process = ProcessInfo.processInfo
        if process.arguments.contains("-mock") { return true }
        if process.environment["QUID_MOCK"] == "1" { return true }
        if process.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return true }
        return false
    }

    static var startsSignedOut: Bool {
        ProcessInfo.processInfo.arguments.contains("-signed-out")
    }

    static let sessionToken = "mock-session-token"
    /// The one-time code the mock backend accepts.
    static let otpCode = "123456"
}

struct MockResponse: Sendable {
    var status: Int = 200
    var body: Data = Data()

    static func json(_ string: String, status: Int = 200) -> MockResponse {
        MockResponse(status: status, body: Data(string.utf8))
    }

    static func empty(status: Int = 204) -> MockResponse {
        MockResponse(status: status, body: Data())
    }
}

/// A request the mock server is answering: method, path, query and decoded JSON body.
struct MockRequest: Sendable {
    let method: String
    let path: String
    let query: String?
    let body: Data

    func decode<T: Decodable>(_ type: T.Type) -> T? {
        try? JSONDecoder.quid.decode(type, from: body)
    }
}

typealias MockHandler = @Sendable (MockRequest) -> MockResponse

/// In-memory router behind `MockURLProtocol`. Static routes are keyed "METHOD /path?query" with a fallback to
/// "METHOD /path"; handler routes get the decoded request and can keep state (see `MockFixtures`).
final class MockServer: @unchecked Sendable {
    static let shared = MockServer()

    private let lock = NSLock()
    private var routes: [String: MockResponse]
    private var handlers: [String: MockHandler]
    private var recorded: [URLRequest] = []
    private var storedLatency: TimeInterval = 0.35

    init() {
        routes = MockFixtures.defaultRoutes()
        handlers = MockFixtures.defaultHandlers()
    }

    /// Simulated network delay, so loading states are visible in the demo. Tests set it to 0.
    var latency: TimeInterval {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedLatency
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            storedLatency = newValue
        }
    }

    func register(_ method: HTTPMethod, _ path: String, _ response: MockResponse) {
        lock.lock()
        defer { lock.unlock() }
        routes[MockServer.key(method.rawValue, path)] = response
        handlers.removeValue(forKey: MockServer.key(method.rawValue, path))
    }

    func register(_ method: HTTPMethod, _ path: String, handler: @escaping MockHandler) {
        lock.lock()
        defer { lock.unlock() }
        handlers[MockServer.key(method.rawValue, path)] = handler
    }

    func reset(latency: TimeInterval = 0.35, signedIn: Bool = true) {
        lock.lock()
        defer { lock.unlock() }
        routes = MockFixtures.defaultRoutes()
        handlers = MockFixtures.defaultHandlers()
        recorded = []
        storedLatency = latency
        MockFixtures.state.reset(complete: signedIn)
    }

    func response(for request: URLRequest, body: Data) -> MockResponse? {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(request)
        guard let method = request.httpMethod, let url = request.url else { return nil }
        let path = url.path(percentEncoded: false)
        let query = url.query(percentEncoded: false)
        if let handler = handlers[MockServer.key(method, path)] {
            return handler(MockRequest(method: method.uppercased(), path: path, query: query, body: body))
        }
        if let query, let exact = routes[MockServer.key(method, path + "?" + query)] {
            return exact
        }
        if let exact = routes[MockServer.key(method, path)] {
            return exact
        }
        // "GET /payments/*" answers any id under that prefix; exact handlers and routes above always win.
        let wanted = MockServer.key(method, path)
        if let (_, handler) = handlers.first(where: { key, _ in key.hasSuffix("/*") && wanted.hasPrefix(String(key.dropLast())) }) {
            return handler(MockRequest(method: method.uppercased(), path: path, query: query, body: body))
        }
        return nil
    }

    /// Every request seen since the last reset, oldest first. Used by tests.
    func recordedRequests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    private static func key(_ method: String, _ pathAndQuery: String) -> String {
        "\(method.uppercased()) \(pathAndQuery)"
    }
}

final class MockURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let server = MockServer.shared
        let body = MockURLProtocol.body(of: request)
        let response = server.response(for: request, body: body)
            ?? .json(#"{"error":"not_found","message":"No mock registered for this route"}"#, status: 404)
        let delay = server.latency
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, let url = self.request.url else { return }
            guard let http = HTTPURLResponse(
                url: url,
                statusCode: response.status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            ) else { return }
            self.client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            if !response.body.isEmpty {
                self.client?.urlProtocol(self, didLoad: response.body)
            }
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

    /// URLSession hands the body to protocols as a stream, not `httpBody`.
    private static func body(of request: URLRequest) -> Data {
        if let data = request.httpBody {
            return data
        }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
