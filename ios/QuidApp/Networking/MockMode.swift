import Foundation

/// MockMode answers every API call in-process so the UI can be built and demoed with no backend.
/// Turn it on with the `-mock` launch argument (the "QuidApp-Mock" scheme does this), `QUID_MOCK=1`, or Xcode previews.
enum MockMode {
    static var isEnabled: Bool {
        let process = ProcessInfo.processInfo
        if process.arguments.contains("-mock") { return true }
        if process.environment["QUID_MOCK"] == "1" { return true }
        if process.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return true }
        return false
    }

    static let sessionToken = "mock-session-token"
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

/// In-memory router behind `MockURLProtocol`. Routes are keyed "METHOD /path?query" and fall back to "METHOD /path".
final class MockServer: @unchecked Sendable {
    static let shared = MockServer()

    private let lock = NSLock()
    private var routes: [String: MockResponse]
    private var recorded: [URLRequest] = []
    private var storedLatency: TimeInterval = 0.35

    init() {
        routes = MockFixtures.defaultRoutes()
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
    }

    func reset(latency: TimeInterval = 0.35) {
        lock.lock()
        defer { lock.unlock() }
        routes = MockFixtures.defaultRoutes()
        recorded = []
        storedLatency = latency
    }

    func response(for request: URLRequest) -> MockResponse? {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(request)
        guard let method = request.httpMethod, let url = request.url else { return nil }
        let path = url.path(percentEncoded: false)
        if let query = url.query(percentEncoded: false), let exact = routes[MockServer.key(method, path + "?" + query)] {
            return exact
        }
        return routes[MockServer.key(method, path)]
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
        let response = server.response(for: request)
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
}
