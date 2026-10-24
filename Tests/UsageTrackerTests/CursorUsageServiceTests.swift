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

    @Test func urlSessionClientUsesAnEphemeralSessionWithoutAutomaticCookieHandling() {
        let configuration = URLSessionHTTPClient().configuration

        #expect(configuration.identifier == nil)
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.httpShouldSetCookies == false)
        #expect(configuration.httpCookieAcceptPolicy == .never)
    }
}
