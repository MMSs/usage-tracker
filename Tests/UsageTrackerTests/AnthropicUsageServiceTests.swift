import Foundation
import Testing
@testable import UsageTracker

/// Routes like `RoutingHTTPClient` but throws `error` for requests ending in `failingSuffix`.
private final class FailingRouteHTTPClient: HTTPClient {
    private let base: RoutingHTTPClient
    private let failingSuffix: String
    private let error: any Error

    init(base: RoutingHTTPClient, failingSuffix: String, error: any Error) {
        self.base = base
        self.failingSuffix = failingSuffix
        self.error = error
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if request.url!.absoluteString.hasSuffix(failingSuffix) {
            throw error
        }

        return try await base.data(for: request)
    }
}

@MainActor
struct AnthropicUsageServiceTests {
    private static let safariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

    private func fixture(_ name: String) throws -> String {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))

        return try String(contentsOf: url, encoding: .utf8)
    }

    private func routes(overage: Bool = true) throws -> [String: RecordingHTTPClient.Response] {
        var routes: [String: RecordingHTTPClient.Response] = [
            "/organizations": .ok(json: try fixture("anthropic-organizations")),
            "/usage": .ok(json: try fixture("anthropic-usage")),
        ]
        if overage {
            routes["/overage_spend_limit"] = .ok(json: try fixture("anthropic-overage-spend-limit"))
            routes["/overage_credit_grant"] = .ok(json: try fixture("anthropic-overage-credit-grant"))
        }

        return routes
    }

    private func count(_ client: RoutingHTTPClient, suffix: String) -> Int {
        client.requests.filter { $0.url!.absoluteString.hasSuffix(suffix) }.count
    }

    @Test func requestsCarryTheClaudeRecipe() async throws {
        let client = RoutingHTTPClient(routes: try routes())
        let service = AnthropicUsageService(client: client)

        _ = try await service.fetchSubscription(sessionKey: "sk-test")

        let organizations = try #require(client.requests.first { $0.url!.path.hasSuffix("/organizations") })
        let usage = try #require(client.requests.first { $0.url!.path.hasSuffix("/usage") })
        for request in [organizations, usage] {
            #expect(request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "Cookie") == "sessionKey=sk-test")
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
            #expect(request.value(forHTTPHeaderField: "Referer") == "https://claude.ai")
            #expect(request.value(forHTTPHeaderField: "Origin") == "https://claude.ai")
            #expect(request.value(forHTTPHeaderField: "User-Agent") == Self.safariUserAgent)
        }
        #expect(organizations.url?.absoluteString == "https://claude.ai/api/organizations")
        #expect(usage.url?.absoluteString == "https://claude.ai/api/organizations/3f1c2a9e-7b4d-4e8a-9c61-0d2f5b8a7e14/usage")
    }

    @Test func snapshotCombinesUsagePlanAndOverage() async throws {
        let service = AnthropicUsageService(client: RoutingHTTPClient(routes: try routes()))

        let snapshot = try await service.fetchSubscription(sessionKey: "k")

        #expect(snapshot.planName == "Max 5x")
        #expect(snapshot.usage.fiveHour?.utilization == 30)
        // A plain JSONDecoder would drop every resets_at.
        #expect(snapshot.usage.fiveHour?.resetsAt != nil)
        #expect(snapshot.spendLimit != nil)
        #expect(snapshot.creditGrant == AnthropicOverageCreditGrant(granted: false, amountMinorUnits: nil, currency: nil))
    }

    @Test func organizationIsResolvedOnceAndCached() async throws {
        let client = RoutingHTTPClient(routes: try routes())
        let service = AnthropicUsageService(client: client)

        _ = try await service.fetchSubscription(sessionKey: "k")
        _ = try await service.fetchSubscription(sessionKey: "k")

        #expect(count(client, suffix: "/organizations") == 1)
        #expect(count(client, suffix: "/usage") == 2)
    }

    @Test func changingTheSessionKeyResolvesTheOrganizationAgain() async throws {
        let client = RoutingHTTPClient(routes: try routes())
        let service = AnthropicUsageService(client: client)

        _ = try await service.fetchSubscription(sessionKey: "key-a")
        _ = try await service.fetchSubscription(sessionKey: "key-b")
        _ = try await service.fetchSubscription(sessionKey: "key-b")

        #expect(count(client, suffix: "/organizations") == 2)
        #expect(count(client, suffix: "/usage") == 3)
    }

    @Test func staleOrganizationIsReResolvedAfter404() async throws {
        let first = """
        [{"uuid":"old-org","rate_limit_tier":"default_claude_pro"}]
        """
        let client = SwitchingOrganizationClient(
            organizations: [first, try fixture("anthropic-organizations")],
            usage: try fixture("anthropic-usage")
        )
        let service = AnthropicUsageService(client: client)

        let snapshot = try await service.fetchSubscription(sessionKey: "k")

        #expect(client.requestedPaths.filter { $0.hasSuffix("/organizations") }.count == 2)
        #expect(client.requestedPaths.contains { $0.hasSuffix("/old-org/usage") })
        #expect(client.requestedPaths.contains { $0.hasSuffix("/3f1c2a9e-7b4d-4e8a-9c61-0d2f5b8a7e14/usage") })
        #expect(snapshot.planName == "Max 5x")
    }

    @Test(arguments: [
        RecordingHTTPClient.Response.status(401),
        .status(404),
        .ok(json: "not json"),
    ])
    func usageFailureClearsTheCacheAndRetriesOnce(response: RecordingHTTPClient.Response) async throws {
        var routes = try routes(overage: false)
        routes["/usage"] = response
        let client = RoutingHTTPClient(routes: routes)
        let service = AnthropicUsageService(client: client)

        await #expect(throws: (any Error).self) {
            try await service.fetchSubscription(sessionKey: "k")
        }

        #expect(count(client, suffix: "/organizations") == 2)
        #expect(count(client, suffix: "/usage") == 2)
    }

    @Test(arguments: ["{}", #"{"five_hour":null,"seven_day":null}"#])
    func emptyUsageIsADecodingFailureAfterOneRetry(json: String) async throws {
        var routes = try routes(overage: false)
        routes["/usage"] = .ok(json: json)
        let client = RoutingHTTPClient(routes: routes)
        let service = AnthropicUsageService(client: client)

        await #expect(throws: FetchError.decoding) {
            try await service.fetchSubscription(sessionKey: "k")
        }

        #expect(count(client, suffix: "/organizations") == 2)
        #expect(count(client, suffix: "/usage") == 2)
    }

    @Test func serverErrorOnUsageIsNotRetried() async throws {
        var routes = try routes(overage: false)
        routes["/usage"] = .status(500)
        let client = RoutingHTTPClient(routes: routes)
        let service = AnthropicUsageService(client: client)

        await #expect(throws: FetchError.httpStatus(500)) {
            try await service.fetchSubscription(sessionKey: "k")
        }

        #expect(count(client, suffix: "/usage") == 1)
        #expect(count(client, suffix: "/organizations") == 1)
    }

    @Test func overageFailuresDoNotFailTheReport() async throws {
        var routes = try routes(overage: false)
        routes["/overage_spend_limit"] = .status(403, headers: ["Content-Type": "application/json"])
        routes["/overage_credit_grant"] = .status(403, headers: ["Content-Type": "application/json"])
        let service = AnthropicUsageService(client: RoutingHTTPClient(routes: routes))

        let snapshot = try await service.fetchSubscription(sessionKey: "k")

        #expect(snapshot.spendLimit == nil)
        #expect(snapshot.creditGrant == nil)
        #expect(snapshot.usage.fiveHour?.utilization == 30)
    }

    @Test func overageDecodingAndNotFoundFailuresYieldNilIndependently() async throws {
        var routes = try routes()
        routes["/overage_spend_limit"] = .ok(json: "{\"unexpected\": true}")
        routes["/overage_credit_grant"] = .status(404)
        let client = RoutingHTTPClient(routes: routes)
        let service = AnthropicUsageService(client: client)

        let snapshot = try await service.fetchSubscription(sessionKey: "k")

        #expect(snapshot.spendLimit == nil)
        #expect(snapshot.creditGrant == nil)
        // Overage failures never clear the cache or retry.
        #expect(count(client, suffix: "/organizations") == 1)
        #expect(count(client, suffix: "/usage") == 1)
    }

    @Test func oneOverageFailureKeepsTheOther() async throws {
        var routes = try routes()
        routes["/overage_spend_limit"] = .status(500)
        let service = AnthropicUsageService(client: RoutingHTTPClient(routes: routes))

        let snapshot = try await service.fetchSubscription(sessionKey: "k")

        #expect(snapshot.spendLimit == nil)
        #expect(snapshot.creditGrant?.granted == false)
    }

    @Test func htmlChallengeIsReportedAsChallenge() async throws {
        var routes = try routes()
        routes["/organizations"] = .status(403, headers: ["Content-Type": "text/html; charset=utf-8"])
        let service = AnthropicUsageService(client: RoutingHTTPClient(routes: routes))

        await #expect(throws: FetchError.challenge) {
            try await service.fetchSubscription(sessionKey: "k")
        }
    }

    @Test func unauthorizedUsageIsExpired() async throws {
        var routes = try routes()
        routes["/usage"] = .status(401)
        let service = AnthropicUsageService(client: RoutingHTTPClient(routes: routes))

        await #expect(throws: FetchError.unauthorized) {
            try await service.fetchSubscription(sessionKey: "k")
        }
    }

    @Test func unauthorizedOrganizationsIsNotRetried() async throws {
        var routes = try routes()
        routes["/organizations"] = .status(401)
        let client = RoutingHTTPClient(routes: routes)
        let service = AnthropicUsageService(client: client)

        await #expect(throws: FetchError.unauthorized) {
            try await service.fetchSubscription(sessionKey: "k")
        }

        #expect(count(client, suffix: "/organizations") == 1)
    }

    private static let twoOrganizations = """
    [{"uuid":"org-a","name":"Personal","capabilities":["chat","claude_pro"],"rate_limit_tier":"default_claude_pro"},
     {"uuid":"org-b","name":"Team","capabilities":["chat","claude_max"],"rate_limit_tier":"default_claude_max_20x"}]
    """

    @Test func chosenOrganizationIsUsedAndNamesThePlan() async throws {
        var routes = try routes(overage: false)
        routes["/organizations"] = .ok(json: Self.twoOrganizations)
        routes["/org-b/usage"] = .ok(json: try fixture("anthropic-usage"))
        let client = RoutingHTTPClient(routes: routes)
        let service = AnthropicUsageService(client: client)

        let snapshot = try await service.fetchSubscription(sessionKey: "k", organizationID: "org-b")

        #expect(count(client, suffix: "/org-b/usage") == 1)
        #expect(count(client, suffix: "/org-a/usage") == 0)
        #expect(snapshot.planName == "Max 20x")
    }

    // MARK: Starting a session

    private func startRoutes(
        completion: [RecordingHTTPClient.Response] = [.ok(json: "")],
        delete: RecordingHTTPClient.Response = .status(204)
    ) throws -> RoutingHTTPClient {
        RoutingHTTPClient(sequences: [
            "/organizations": [.ok(json: try fixture("anthropic-organizations"))],
            "/chat_conversations": [.status(201)],
            "/completion": completion,
            // The conversation id is random, so only the catch-all can match the DELETE.
            "": [delete],
        ])
    }

    private func body(_ request: URLRequest) throws -> [String: String] {
        let data = try #require(request.httpBody)

        return try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
    }

    private func startRequests(_ client: RoutingHTTPClient) -> [URLRequest] {
        client.requests.filter { $0.httpMethod != "GET" }
    }

    @Test func startingASessionCreatesSendsAndDeletesAConversation() async throws {
        let client = try startRoutes()
        let service = AnthropicUsageService(client: client)

        try await service.startSession(sessionKey: "sk-test", organizationID: nil, model: "test-model")

        let requests = startRequests(client)
        #expect(requests.map(\.httpMethod) == ["POST", "POST", "DELETE"])
        let org = "3f1c2a9e-7b4d-4e8a-9c61-0d2f5b8a7e14"
        let base = "https://claude.ai/api/organizations/\(org)/chat_conversations"

        let create = try body(requests[0])
        let conversation = try #require(create["uuid"])
        #expect(conversation == conversation.lowercased())
        #expect(UUID(uuidString: conversation) != nil)
        #expect(create == ["uuid": conversation, "name": ""])
        #expect(requests[0].url?.absoluteString == base)
        #expect(requests[1].url?.absoluteString == "\(base)/\(conversation)/completion")
        #expect(requests[2].url?.absoluteString == "\(base)/\(conversation)")
        #expect(try body(requests[1]) == [
            "prompt": "ping", "model": "test-model", "timezone": TimeZone.current.identifier,
        ])
        #expect(requests[2].httpBody == nil)

        for request in requests {
            #expect(request.value(forHTTPHeaderField: "Cookie") == "sessionKey=sk-test")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            #expect(request.value(forHTTPHeaderField: "Origin") == "https://claude.ai")
            #expect(request.value(forHTTPHeaderField: "Referer") == "https://claude.ai/new")
            #expect(request.value(forHTTPHeaderField: "User-Agent") == Self.safariUserAgent)
            #expect(request.value(forHTTPHeaderField: "anthropic-version") == nil)
        }
        #expect(requests[1].value(forHTTPHeaderField: "Accept") == "text/event-stream")
    }

    @Test func aFailedDeleteStillCountsAsStarted() async throws {
        let client = try startRoutes(delete: .status(500))
        let service = AnthropicUsageService(client: client)

        try await service.startSession(sessionKey: "k", organizationID: nil, model: "test-model")

        #expect(startRequests(client).map(\.httpMethod) == ["POST", "POST", "DELETE"])
    }

    @Test func aFailedCompletionThrowsAndStillDeletes() async throws {
        let client = try startRoutes(completion: [.status(403, headers: ["Content-Type": "application/json"])])
        let service = AnthropicUsageService(client: client)

        await #expect(throws: FetchError.unauthorized) {
            try await service.startSession(sessionKey: "k", organizationID: nil, model: "test-model")
        }

        #expect(startRequests(client).map(\.httpMethod) == ["POST", "POST", "DELETE"])
    }

    /// A cancelled start must not leave empty chats piling up.
    @Test func aCancelledCompletionStillDeletesTheConversation() async throws {
        let client = CancellableHTTPClient(routes: try startRoutes(), heldSuffix: "/completion")
        let service = AnthropicUsageService(client: client)

        let start = Task { try await service.startSession(sessionKey: "k", organizationID: nil, model: "test-model") }
        for _ in 0..<200 where !client.isHolding {
            await Task.yield()
        }
        #expect(client.isHolding)
        start.cancel()
        client.gate.resume()

        await #expect(throws: CancellationError.self) { try await start.value }
        let sent = client.sent.filter { $0.httpMethod != "GET" }
        #expect(sent.map(\.httpMethod) == ["POST", "DELETE"])
    }

    @Test(arguments: [400, 404])
    func aRefusedModelRetriesOnceWithoutIt(status: Int) async throws {
        let client = try startRoutes(completion: [.status(status), .ok(json: "")])
        let service = AnthropicUsageService(client: client)

        try await service.startSession(sessionKey: "k", organizationID: nil, model: "test-model")

        let completions = client.requests.filter { $0.url!.path.hasSuffix("/completion") }
        #expect(completions.count == 2)
        #expect(try body(completions[0])["model"] == "test-model")
        #expect(try body(completions[1])["model"] == nil)
        #expect(try body(completions[1])["prompt"] == "ping")
        #expect(startRequests(client).last?.httpMethod == "DELETE")
    }

    @Test func aRefusedRetryThrowsItsError() async throws {
        let client = try startRoutes(completion: [.status(400), .status(500)])
        let service = AnthropicUsageService(client: client)

        await #expect(throws: FetchError.httpStatus(500)) {
            try await service.startSession(sessionKey: "k", organizationID: nil, model: "test-model")
        }
    }

    @Test func severalOrganizationsAndNoChoiceThrowsNeedsOrganization() async throws {
        var routes = try routes()
        routes["/organizations"] = .ok(json: Self.twoOrganizations)
        let service = AnthropicUsageService(client: RoutingHTTPClient(routes: routes))

        await #expect(throws: FetchError.needsOrganizationChoice) {
            try await service.startSession(sessionKey: "k", organizationID: nil, model: "test-model")
        }
    }

    @Test func severalOrganizationsAndNoChoiceNeedAChoiceWithoutFetchingUsage() async throws {
        var routes = try routes()
        routes["/organizations"] = .ok(json: Self.twoOrganizations)
        let client = RoutingHTTPClient(routes: routes)
        let service = AnthropicUsageService(client: client)

        await #expect(throws: FetchError.needsOrganizationChoice) {
            try await service.fetchSubscription(sessionKey: "k", organizationID: nil)
        }

        #expect(count(client, suffix: "/usage") == 0)
        #expect(count(client, suffix: "/overage_spend_limit") == 0)
        #expect(service.organizations(sessionKey: "k").map(\.uuid) == ["org-a", "org-b"])
        #expect(service.organizations(sessionKey: "other").isEmpty)
    }

    @Test func aChoiceNoLongerListedNeedsANewOne() async throws {
        var routes = try routes()
        routes["/organizations"] = .ok(json: Self.twoOrganizations)
        let client = RoutingHTTPClient(routes: routes)
        let service = AnthropicUsageService(client: client)

        await #expect(throws: FetchError.needsOrganizationChoice) {
            try await service.fetchSubscription(sessionKey: "k", organizationID: "gone")
        }

        #expect(count(client, suffix: "/usage") == 0)
    }

    @Test func aLoneOrganizationIsUsedWhateverTheStoredChoice() async throws {
        let client = RoutingHTTPClient(routes: try routes())
        let service = AnthropicUsageService(client: client)

        let snapshot = try await service.fetchSubscription(sessionKey: "k", organizationID: "gone")

        #expect(count(client, suffix: "/3f1c2a9e-7b4d-4e8a-9c61-0d2f5b8a7e14/usage") == 1)
        #expect(snapshot.planName == "Max 5x")
    }

    @Test func needingAChoiceListsTheOrganizationsAgainNextTime() async throws {
        var routes = try routes(overage: false)
        routes["/organizations"] = .ok(json: Self.twoOrganizations)
        routes["/org-a/usage"] = .ok(json: try fixture("anthropic-usage"))
        let client = RoutingHTTPClient(routes: routes)
        let service = AnthropicUsageService(client: client)

        await #expect(throws: FetchError.needsOrganizationChoice) {
            try await service.fetchSubscription(sessionKey: "k", organizationID: nil)
        }
        let snapshot = try await service.fetchSubscription(sessionKey: "k", organizationID: "org-a")
        _ = try await service.fetchSubscription(sessionKey: "k", organizationID: "org-a")

        #expect(count(client, suffix: "/organizations") == 2)
        #expect(count(client, suffix: "/org-a/usage") == 2)
        #expect(snapshot.planName == "Pro")
    }

    @Test func aChosenOrganizationThatDisappearsNeedsANewChoice() async throws {
        let client = SwitchingOrganizationClient(
            organizations: [
                #"[{"uuid":"old-org"},{"uuid":"other-org"}]"#,
                #"[{"uuid":"other-org"},{"uuid":"3f1c2a9e-7b4d-4e8a-9c61-0d2f5b8a7e14"}]"#,
            ],
            usage: try fixture("anthropic-usage")
        )
        let service = AnthropicUsageService(client: client)

        await #expect(throws: FetchError.needsOrganizationChoice) {
            try await service.fetchSubscription(sessionKey: "k", organizationID: "old-org")
        }

        #expect(client.requestedPaths.filter { $0.hasSuffix("/usage") } == ["/api/organizations/old-org/usage"])
        #expect(service.organizations(sessionKey: "k").map(\.uuid) == ["other-org", "3f1c2a9e-7b4d-4e8a-9c61-0d2f5b8a7e14"])
    }

    @Test func malformedOrganizationElementsAreSkipped() async throws {
        var routes = try routes(overage: false)
        routes["/organizations"] = .ok(json: """
        [{"name":"no uuid","capabilities":["chat"]}, "garbage", {"uuid":7},
         {"uuid":"good-org","capabilities":["chat"]}]
        """)
        routes["/good-org/usage"] = .ok(json: try fixture("anthropic-usage"))
        let client = RoutingHTTPClient(routes: routes)
        let service = AnthropicUsageService(client: client)

        _ = try await service.fetchSubscription(sessionKey: "k")

        #expect(count(client, suffix: "/good-org/usage") == 1)
    }

    @Test(arguments: [
        #"{"five_hour":{"utilization":3,"resets_at":"soon"},"seven_day":{"utilization":1,"resets_at":null}}"#,
        #"{"five_hour":{"utilization":3,"resets_at":null},"seven_day":{"utilization":1,"resets_at":"soon"}}"#,
    ])
    func anUnreadableSessionResetIsADecodingError(json: String) async throws {
        var routes = try routes(overage: false)
        routes["/usage"] = .ok(json: json)
        let service = AnthropicUsageService(client: RoutingHTTPClient(routes: routes))

        await #expect(throws: FetchError.decoding) {
            try await service.fetchSubscription(sessionKey: "k")
        }
    }

    @Test func emptyOrganizationListIsAFailure() async throws {
        var routes = try routes()
        routes["/organizations"] = .ok(json: "[]")
        let client = RoutingHTTPClient(routes: routes)
        let service = AnthropicUsageService(client: client)

        await #expect(throws: FetchError.decoding) {
            try await service.fetchSubscription(sessionKey: "k")
        }

        #expect(count(client, suffix: "/usage") == 0)
    }

    @Test(arguments: ["/organizations", "/usage", "/overage_spend_limit", "/overage_credit_grant"])
    func cancellationPropagatesFromAnyRequestWithoutRetry(failingSuffix: String) async throws {
        let base = RoutingHTTPClient(routes: try routes())
        let client = FailingRouteHTTPClient(base: base, failingSuffix: failingSuffix, error: CancellationError())
        let service = AnthropicUsageService(client: client)

        await #expect(throws: CancellationError.self) {
            try await service.fetchSubscription(sessionKey: "k")
        }

        #expect(count(base, suffix: "/organizations") <= 1)
        #expect(count(base, suffix: "/usage") <= 1)
    }
}

/// Serves a different organization list per `/organizations` call; only the
/// organization with uuid `3f1c...` has a working `/usage`.
private final class SwitchingOrganizationClient: HTTPClient {
    private(set) var requestedPaths: [String] = []
    private var organizations: [String]
    private let usage: String

    init(organizations: [String], usage: String) {
        self.organizations = organizations
        self.usage = usage
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url!
        requestedPaths.append(url.path)
        let status: Int
        var body = ""

        if url.path.hasSuffix("/organizations") {
            status = 200
            body = organizations.count > 1 ? organizations.removeFirst() : organizations[0]
        } else if url.path.hasSuffix("/3f1c2a9e-7b4d-4e8a-9c61-0d2f5b8a7e14/usage") {
            status = 200
            body = usage
        } else {
            status = 404
        }

        return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

@MainActor
struct RoutingHTTPClientTests {
    private func status(_ client: RoutingHTTPClient, _ url: String) async throws -> Int {
        let (_, response) = try await client.data(for: URLRequest(url: URL(string: url)!))

        return (response as! HTTPURLResponse).statusCode
    }

    @Test func longestSuffixWinsQueriesMatchAndUnmatchedIs404() async throws {
        let client = RoutingHTTPClient(routes: [
            "/cost_report": .status(500),
            "?limit=31": .status(401),
            "page=p2": .status(204),
        ])

        #expect(try await status(client, "https://x.test/v1/cost_report") == 500)
        #expect(try await status(client, "https://x.test/v1/cost_report?limit=31&page=p2") == 204)
        #expect(try await status(client, "https://x.test/v1/cost_report?limit=31") == 401)
        #expect(try await status(client, "https://x.test/v1/other") == 404)
        #expect(client.requests.count == 4)
    }
}
