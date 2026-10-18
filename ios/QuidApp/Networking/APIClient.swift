import Foundation

/// The single HTTP client. URLSession + Codable; every failure becomes an `AppError`.
final class APIClient: Sendable {
    let baseURL: URL
    private let session: URLSession
    private let tokenStore: any TokenStore

    init(baseURL: URL, tokenStore: any TokenStore, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.tokenStore = tokenStore
        self.session = session
    }

    /// A client whose requests never leave the process: `MockServer` answers with canned JSON.
    static func mock(tokenStore: any TokenStore) -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return APIClient(
            baseURL: URL(string: "https://mock.quid.invalid")!,
            tokenStore: tokenStore,
            session: URLSession(configuration: configuration)
        )
    }

    func send<Response: Decodable>(_ endpoint: Endpoint<Response>) async throws -> Response {
        let request = try makeRequest(for: endpoint)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw AppError.from(urlError: urlError)
        } catch {
            throw AppError.unknown(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw AppError.unknown("Unexpected response from the server.")
        }

        switch http.statusCode {
        case 200..<300:
            if Response.self == Empty.self, let empty = Empty() as? Response {
                return empty
            }
            do {
                return try JSONDecoder.quid.decode(Response.self, from: data)
            } catch {
                throw AppError.decoding
            }
        case 400:
            throw AppError.validation(errorMessage(from: data) ?? "That request wasn't valid.")
        case 401:
            throw AppError.unauthorized
        case 403:
            throw AppError.forbidden
        case 404:
            throw AppError.notFound
        case 429:
            throw AppError.rateLimited
        default:
            throw AppError.server(status: http.statusCode, message: errorMessage(from: data))
        }
    }

    private func makeRequest<Response>(for endpoint: Endpoint<Response>) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = baseURL.scheme
        components.host = baseURL.host()
        components.port = baseURL.port
        let basePath = baseURL.path().hasSuffix("/") ? String(baseURL.path().dropLast()) : baseURL.path()
        let endpointPath = endpoint.path.hasPrefix("/") ? endpoint.path : "/" + endpoint.path
        components.path = basePath + endpointPath
        components.queryItems = endpoint.query.isEmpty ? nil : endpoint.query
        guard let url = components.url else {
            throw AppError.unknown("Could not build a URL for \(endpoint.path).")
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = endpoint.body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder.quid.encode(body)
        }
        if endpoint.requiresAuth, let token = tokenStore.load() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func errorMessage(from data: Data) -> String? {
        (try? JSONDecoder.quid.decode(ErrorBodyDTO.self, from: data))?.message
    }
}
