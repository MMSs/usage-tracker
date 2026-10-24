import Foundation
import Testing
@testable import UsageTracker

@MainActor
struct CursorUsageServiceTests {
    @Test func requestUsesSessionCookie() async throws {
        let client = RecordingHTTPClient(response: .ok(json: """
        {"billingCycleStart":"2026-09-01T00:00:00Z","billingCycleEnd":"2026-10-01T00:00:00Z","individualUsage":{"overall":{"used":5000,"limit":22000}},"isUnlimited":false}
        """))
        let service = CursorUsageService(client: client)

        _ = try await service.fetchUsage(token: "session-token")

        #expect(client.lastRequest?.value(forHTTPHeaderField: "Cookie") == "WorkosCursorSessionToken=session-token")
    }

    @Test func decodesPersonalPlanUsageWithoutOverall() async throws {
        let client = RecordingHTTPClient(response: .ok(json: """
        {"billingCycleStart":"2026-09-19T17:34:26.859Z","billingCycleEnd":"2026-10-19T17:34:26.859Z","membershipType":"free","limitType":"user","isUnlimited":false,"individualUsage":{"plan":{"enabled":true,"used":0,"limit":0,"remaining":0,"autoPercentUsed":4,"totalPercentUsed":2},"onDemand":{"enabled":false,"used":0,"limit":null,"remaining":null}},"teamUsage":{}}
        """))
        let service = CursorUsageService(client: client)

        let response = try await service.fetchUsage(token: "t")

        #expect(response.individualUsage.overall == .init(used: 0, limit: nil, percentUsed: 2, percentSplit: .init(auto: 4, api: 0)))
    }

    @Test func decodesPaidPersonalPlanLimitAndOmittedZeroUsage() async throws {
        let client = RecordingHTTPClient(response: .ok(json: """
        {"billingCycleStart":"2026-09-01T00:00:00Z","billingCycleEnd":"2026-10-01T00:00:00Z","isUnlimited":false,"individualUsage":{"plan":{"limit":2000}}}
        """))
        let service = CursorUsageService(client: client)

        let response = try await service.fetchUsage(token: "t")

        #expect(response.individualUsage.overall == .init(used: 0, limit: 2000))
    }

    private func dailySpend(
        _ json: String,
        client: RoutingHTTPClient? = nil
    ) async throws -> (response: DailySpendResponse, client: RoutingHTTPClient) {
        let client = client ?? RoutingHTTPClient(routes: [
            "get-user-organizations": .ok(json: "{}"),
            "get-daily-spend-by-category": .ok(json: json),
        ])
        let service = CursorUsageService(client: client)
        let start = Date(timeIntervalSince1970: 1_792_368_000)
        let response = try await service.fetchDailySpend(
            token: "t", periodStart: start, periodEnd: start.addingTimeInterval(30 * 86400)
        )

        return (response, client)
    }

    private func count(_ client: RoutingHTTPClient, suffix: String) -> Int {
        client.requests.filter { $0.url!.absoluteString.hasSuffix(suffix) }.count
    }

    // A free account has no daily-spend list; Cursor omits empty repeated fields.
    @Test(arguments: ["{}", #"{"categories":[]}"#, #"{"dailySpend":[]}"#])
    func emptyDailySpendDecodesAsNoDays(json: String) async throws {
        let (response, client) = try await dailySpend(json)

        #expect(response.dailySpend.isEmpty)
        // Not a decoding failure, so no identity retry.
        #expect(count(client, suffix: "get-user-organizations") == 1)
        #expect(count(client, suffix: "get-daily-spend-by-category") == 1)
    }

    @Test func populatedDailySpendIgnoresTheExtraKeys() async throws {
        let url = try #require(Bundle.module.url(forResource: "cursor-daily-spend", withExtension: "json", subdirectory: "Fixtures"))
        let (response, client) = try await dailySpend(String(contentsOf: url, encoding: .utf8))

        #expect(response.dailySpend.count == 5)
        #expect(response.dailySpend[0] == .init(day: "1792368000000", category: "claude-opus-5-5-low", spendCents: 95, totalTokens: "969191"))
        #expect(count(client, suffix: "get-daily-spend-by-category") == 1)
    }

    @Test func malformedDailySpendStillRetriesTheIdentityOnce() async throws {
        let client = RoutingHTTPClient(routes: [
            "get-user-organizations": .ok(json: "{}"),
            "get-daily-spend-by-category": .ok(json: #"{"dailySpend":"nope"}"#),
        ])

        await #expect(throws: FetchError.decoding) {
            _ = try await dailySpend("", client: client)
        }
        #expect(count(client, suffix: "get-daily-spend-by-category") == 2)
    }

    @Test func unauthorizedResponseMapsToUnauthorizedError() async {
        let service = CursorUsageService(client: RecordingHTTPClient(response: .status(401)))

        await #expect(throws: FetchError.unauthorized) {
            try await service.fetchUsage(token: "session-token")
        }
    }

    @Test func htmlForbiddenIsAChallengeNotExpiry() async {
        let client = RecordingHTTPClient(response: .status(403, headers: ["Content-Type": "text/html; charset=utf-8"]))
        let service = CursorUsageService(client: client)

        await #expect(throws: FetchError.challenge) {
            try await service.fetchUsage(token: "session-token")
        }
    }

    @Test func jsonForbiddenMapsToUnauthorized() async {
        let client = RecordingHTTPClient(response: .status(403, headers: ["Content-Type": "application/json"]))
        let service = CursorUsageService(client: client)

        await #expect(throws: FetchError.unauthorized) {
            try await service.fetchUsage(token: "session-token")
        }
    }

    @Test func otherStatusMapsToHTTPStatus() async {
        let service = CursorUsageService(client: RecordingHTTPClient(response: .status(500)))

        await #expect(throws: FetchError.httpStatus(500)) {
            try await service.fetchUsage(token: "session-token")
        }
    }

    @Test func cancelledRequestIsCancellationNotTransport() async {
        for error: any Error in [URLError(.cancelled), CancellationError()] {
            let service = CursorUsageService(client: ThrowingHTTPClient(error: error))
            // URLSession reports a cancelled task as URLError.cancelled.
            let task = Task { try await service.fetchUsage(token: "session-token") }
            task.cancel()

            await #expect(throws: CancellationError.self) {
                try await task.value
            }
        }
    }

    @Test func otherRequestFailureIsTransport() async {
        let service = CursorUsageService(client: ThrowingHTTPClient(error: URLError(.notConnectedToInternet)))

        await #expect(throws: FetchError.transport) {
            try await service.fetchUsage(token: "session-token")
        }
    }

    @Test func urlSessionClientUsesAnEphemeralSessionWithoutAutomaticCookieHandling() {
        let configuration = URLSessionHTTPClient().configuration

        #expect(configuration.identifier == nil)
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.httpShouldSetCookies == false)
        #expect(configuration.httpCookieAcceptPolicy == .never)
    }

    /// Every refresh repeats the same URL (the API month's bounds change
    /// once a month), so a cached response would pass for a fresh one.
    @Test func urlSessionClientNeverAnswersFromACache() {
        let configuration = URLSessionHTTPClient().configuration

        #expect(configuration.urlCache == nil)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
    }

    /// The default resource timeout is seven days: a trickling response
    /// would hold its provider's refresh cycle, and its other half, that long.
    @Test func urlSessionClientGivesUpWellWithinARefreshInterval() {
        let configuration = URLSessionHTTPClient().configuration

        #expect(configuration.timeoutIntervalForRequest == 30)
        #expect(configuration.timeoutIntervalForResource == 60)
    }
}
