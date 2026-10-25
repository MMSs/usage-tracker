import Foundation

enum FetchError: Error, Equatable {
    case unauthorized
    case httpStatus(Int)
    /// HTTP 429; `until` is the response's `Retry-After`, when it had a readable one.
    case rateLimited(until: Date?)
    case challenge
    case invalidResponse
    case decoding
    /// No response from a server that is down, unknown, untrusted or slow.
    case transport
    /// No response because the Mac has no connection.
    case offline
    /// The credential sees several organizations and none listed is chosen.
    case needsOrganizationChoice
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
        // Responses are small JSON. A refresh cycle waits for its fetches, so
        // a trickling response must not hold it (and the provider's other
        // half) for the default seven days; a minute is under the default
        // five-minute interval (`RefreshInterval.default`).
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        session = URLSession(configuration: configuration)
    }

    var configuration: URLSessionConfiguration {
        session.configuration
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}
