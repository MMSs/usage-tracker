import Foundation
@testable import UsageTracker

/// Answers each request from the response whose key is the longest suffix of
/// the request's full URL string (path plus query); anything unmatched is a 404.
/// A route given several responses answers with the next one each time it is
/// matched and repeats the last.
final class RoutingHTTPClient: HTTPClient {
    private(set) var requests: [URLRequest] = []
    private let routes: [(suffix: String, responses: [RecordingHTTPClient.Response])]
    private var served: [String: Int] = [:]

    convenience init(routes: [String: RecordingHTTPClient.Response]) {
        self.init(sequences: routes.mapValues { [$0] })
    }

    init(sequences: [String: [RecordingHTTPClient.Response]]) {
        routes = sequences
            .map { (suffix: $0.key, responses: $0.value) }
            .sorted { $0.suffix.count > $1.suffix.count }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let url = request.url!
        let response: RecordingHTTPClient.Response
        if let route = routes.first(where: { url.absoluteString.hasSuffix($0.suffix) }), !route.responses.isEmpty {
            let index = served[route.suffix, default: 0]
            served[route.suffix] = index + 1
            response = route.responses[min(index, route.responses.count - 1)]
        } else {
            response = .status(404)
        }
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
