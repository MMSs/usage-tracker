import Foundation
import Testing
@testable import UsageTracker

@MainActor
struct HTTPResponseHandlerTests {
    private let request = URLRequest(url: URL(string: "https://example.com/api")!)

    @Test func cancelledURLErrorBecomesCancellationError() async {
        let client = ThrowingHTTPClient(error: URLError(.cancelled))
        let request = request
        // Main-actor work cannot start before this test suspends, so the cancel lands first.
        let task = Task { try await HTTPResponseHandler.data(for: request, client: client) }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    /// Only a cancelled task is "not a failure"; a session that cancels on
    /// its own must not leave the half silently showing its old report.
    @Test func cancelledURLErrorWithoutTaskCancellationIsTransport() async {
        let client = ThrowingHTTPClient(error: URLError(.cancelled))

        await #expect(throws: FetchError.transport) {
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

    @Test func tooManyRequestsIsRateLimitedUntilRetryAfterSeconds() async throws {
        let client = RecordingHTTPClient(response: .status(429, headers: ["Retry-After": "120"]))
        let before = Date()

        let error = await #expect(throws: FetchError.self) {
            try await HTTPResponseHandler.data(for: request, client: client)
        }

        guard case let .rateLimited(until)? = error else {
            Issue.record("expected rateLimited, got \(String(describing: error))")
            return
        }
        let date = try #require(until)
        #expect(date >= before.addingTimeInterval(120))
        #expect(date <= Date().addingTimeInterval(120))
    }

    @Test func tooManyRequestsWithoutRetryAfterIsRateLimitedWithNoDate() async {
        let client = RecordingHTTPClient(response: .status(429))

        await #expect(throws: FetchError.rateLimited(until: nil)) {
            try await HTTPResponseHandler.data(for: request, client: client)
        }
    }

    @Test func tooManyRequestsHonoursAnHTTPDate() async {
        let client = RecordingHTTPClient(response: .status(429, headers: ["Retry-After": "Sat, 24 Oct 2026 21:05:00 GMT"]))

        await #expect(throws: FetchError.rateLimited(until: Date(timeIntervalSince1970: 1_792_875_900))) {
            try await HTTPResponseHandler.data(for: request, client: client)
        }
    }

    @Test(arguments: [
        ("0", 0.0),
        ("90", 90),
        (" 30 ", 30),
    ])
    func retryAfterSecondsCountFromNow(value: String, seconds: Double) {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(HTTPResponseHandler.retryAfter(value, now: now) == now.addingTimeInterval(seconds))
    }

    @Test(arguments: [
        "Sat, 24 Oct 2026 21:05:00 GMT",
        "Saturday, 24-Oct-26 21:05:00 GMT",
        "Sat Oct 24 21:05:00 2026",
    ])
    func retryAfterAcceptsEveryHTTPDateForm(value: String) {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(HTTPResponseHandler.retryAfter(value, now: now) == Date(timeIntervalSince1970: 1_792_875_900))
    }

    @Test(arguments: [nil, "", "soon", "-5", "1.5", "12abc"])
    func unreadableRetryAfterIsIgnored(value: String?) {
        #expect(HTTPResponseHandler.retryAfter(value, now: Date(timeIntervalSince1970: 1_000_000)) == nil)
    }

    @Test func decodeFailureIsDecodingError() {
        #expect(throws: FetchError.decoding) {
            try HTTPResponseHandler.decode([String].self, from: Data("{}".utf8))
        }
    }
}
