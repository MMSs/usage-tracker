import Foundation
@testable import UsageTracker

/// Answers each request from the response whose key is the longest suffix of
/// the request's full URL string (path plus query); anything unmatched is a 404.
final class RoutingHTTPClient: HTTPClient {
    private(set) var requests: [URLRequest] = []
    private let routes: [(suffix: String, response: RecordingHTTPClient.Response)]

    init(routes: [String: RecordingHTTPClient.Response]) {
        self.routes = routes
            .map { (suffix: $0.key, response: $0.value) }
            .sorted { $0.suffix.count > $1.suffix.count }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let url = request.url!
        let response = routes.first { url.absoluteString.hasSuffix($0.suffix) }?.response ?? .status(404)
        let statusCode: Int
        let data: Data
        let headers: [String: String]?

        switch response {
        case let .ok(json):
            statusCode = 200
            data = Data(json.utf8)
            headers = nil
        case let .status(code, responseHeaders):
            statusCode = code
            data = Data()
            headers = responseHeaders
        }

        return (data, HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers
        )!)
    }
}
