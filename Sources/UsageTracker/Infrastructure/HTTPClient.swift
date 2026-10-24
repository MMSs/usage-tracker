import Foundation

enum FetchError: Error, Equatable {
    case unauthorized
    case httpStatus(Int)
    /// HTTP 429; `until` is the response's `Retry-After`, when it had a readable one.
    case rateLimited(until: Date?)
    case challenge
    case invalidResponse
    case decoding
    case transport
}

@MainActor
protocol HTTPClient {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

final class URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        // A refresh must reach the server; usage changes behind a URL that does not.
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    var configuration: URLSessionConfiguration {
        session.configuration
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}
