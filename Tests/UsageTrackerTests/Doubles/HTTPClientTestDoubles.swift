import Foundation
@testable import UsageTracker

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
