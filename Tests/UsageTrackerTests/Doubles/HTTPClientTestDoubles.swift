import Foundation
@testable import UsageTracker

/// Fails every request with `error`, as URLSession does when offline or cancelled.
final class ThrowingHTTPClient: HTTPClient {
    private let error: any Error

    init(error: any Error) {
        self.error = error
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        throw error
    }
}

final class RecordingHTTPClient: HTTPClient {
    enum Response {
        case ok(json: String)
        case status(Int, headers: [String: String] = [:])
    }

    var lastRequest: URLRequest?
    private let response: Response

    init(response: Response) {
        self.response = response
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
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
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers
        )!)
    }
}

/// Answers like `routes`, but behaves as URLSession does under cancellation:
/// a request from a cancelled task fails with `URLError(.cancelled)` and
/// never reaches the server. Requests whose URL ends in `heldSuffix` wait
/// for `gate` first.
final class CancellableHTTPClient: HTTPClient {
    private let routes: RoutingHTTPClient
    private let heldSuffix: String
    let gate = SuspendedGate()
    /// Requests that reached the server.
    private(set) var sent: [URLRequest] = []
    /// True once a held request is waiting on the gate.
    private(set) var isHolding = false

    init(routes: RoutingHTTPClient, heldSuffix: String) {
        self.routes = routes
        self.heldSuffix = heldSuffix
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if request.url?.absoluteString.hasSuffix(heldSuffix) == true {
            isHolding = true
            await gate.wait()
        }

        guard !Task.isCancelled else {
            throw URLError(.cancelled)
        }

        sent.append(request)
        return try await routes.data(for: request)
    }
}
