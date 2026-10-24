import Foundation
import Testing
@testable import UsageTracker

@MainActor
struct HTTPResponseHandlerTests {
    private let request = URLRequest(url: URL(string: "https://example.com/api")!)

    @Test func cancelledURLErrorBecomesCancellationError() async {
        let client = ThrowingHTTPClient(error: URLError(.cancelled))

        await #expect(throws: CancellationError.self) {
            try await HTTPResponseHandler.data(for: request, client: client)
        }
    }

    @Test func offlineTransportFailureIsTransport() async {
        let client = ThrowingHTTPClient(error: URLError(.notConnectedToInternet))

        await #expect(throws: FetchError.transport) {
            try await HTTPResponseHandler.data(for: request, client: client)
        }
    }

    @Test func htmlForbiddenIsChallenge() async {
        let client = RecordingHTTPClient(response: .status(403, headers: ["Content-Type": "text/html; charset=utf-8"]))

        await #expect(throws: FetchError.challenge) {
            try await HTTPResponseHandler.data(for: request, client: client)
        }
    }

    @Test func jsonForbiddenIsUnauthorized() async {
        let client = RecordingHTTPClient(response: .status(403, headers: ["Content-Type": "application/json"]))

        await #expect(throws: FetchError.unauthorized) {
            try await HTTPResponseHandler.data(for: request, client: client)
        }
    }

    @Test func serverErrorKeepsStatus() async {
        let client = RecordingHTTPClient(response: .status(500))

        await #expect(throws: FetchError.httpStatus(500)) {
            try await HTTPResponseHandler.data(for: request, client: client)
        }
    }

    @Test func decodeFailureIsDecodingError() {
        #expect(throws: FetchError.decoding) {
            try HTTPResponseHandler.decode([String].self, from: Data("{}".utf8))
        }
    }
}
