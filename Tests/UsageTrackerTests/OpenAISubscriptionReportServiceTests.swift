import Foundation
import Testing
@testable import UsageTracker

@MainActor
struct OpenAISubscriptionReportServiceTests {
    private final class StubUsage: OpenAIUsageFetching {
        let response: OpenAIUsageResponse
        /// Access tokens answered with 401, as an expired token is.
        var rejected: Set<String> = []
        /// Access tokens answered with a JSON 403, which a new token cannot fix.
        var forbidden: Set<String> = []
        private(set) var accessTokens: [String] = []

        init(response: OpenAIUsageResponse) {
            self.response = response
        }

        func fetchUsage(auth: CodexAuth) async throws -> OpenAIUsageResponse {
            accessTokens.append(auth.accessToken)
            if rejected.contains(auth.accessToken) {
                throw OpenAIUsageError.accessTokenExpired
            }
            if forbidden.contains(auth.accessToken) {
                throw FetchError.unauthorized
            }
            return response
        }

        /// The access token and model of each session start.
        private(set) var starts: [(accessToken: String, model: String)] = []
        /// Thrown by every start whose token is not rejected, when set.
        var startError: FetchError?

        func startSession(auth: CodexAuth, model: String) async throws {
            starts.append((auth.accessToken, model))
            if rejected.contains(auth.accessToken) {
                throw OpenAIUsageError.accessTokenExpired
            }
            if let startError {
                throw startError
            }
        }
    }

    /// Holds every renewal mid-flight until opened, so a second renewal fails
    /// the test instead of stranding the first.
    @MainActor
    private final class RenewalGate {
        private var isOpen = false
        private var waiting: [CheckedContinuation<Void, Never>] = []
        private var startWaiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            guard !isOpen else {
                return
            }

            startWaiters.forEach { $0.resume() }
            startWaiters.removeAll()

            await withCheckedContinuation { waiting.append($0) }
        }

        func waitUntilStarted() async {
            guard waiting.isEmpty else {
                return
            }

            await withCheckedContinuation { startWaiters.append($0) }
        }

        func open() {
            isOpen = true
            waiting.forEach { $0.resume() }
            waiting.removeAll()
        }
    }

    private final class StubTokens: OpenAITokenRenewing {
        var result: Result<CodexTokenGrant, FetchError>
        /// Holds each renewal mid-flight until opened, when set.
        var gate: RenewalGate?
        /// Runs just before the grant is returned, while the renewal is in flight.
        var whileRenewing: (() -> Void)?
        private(set) var refreshTokens: [String] = []

        init(grant: CodexTokenGrant) {
            result = .success(grant)
        }

        func renew(refreshToken: String) async throws -> CodexTokenGrant {
            refreshTokens.append(refreshToken)
            await gate?.wait()
            whileRenewing?()
            return try result.get()
        }
    }

    private static let key = CredentialKey(provider: .openai, fieldID: "auth-json")
    private static let today = Date(timeIntervalSince1970: 1_792_800_000)
    private static let renewedAt = Date(timeIntervalSince1970: 1_792_800_123)

    private static func bundle(access: String = "old-access", refresh: String = "old-refresh") -> String {
        """
        {"auth_mode":"chatgpt","future_field":{"a":1},"last_refresh":"2026-01-01T00:00:00.000Z",
         "tokens":{"access_token":"\(access)","refresh_token":"\(refresh)","id_token":"old-id","account_id":"acct-file"}}
        """
    }

    private static func grant() throws -> CodexTokenGrant {
        let url = try #require(Bundle.module.url(forResource: "openai-token-refresh", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(CodexTokenGrant.self, from: Data(contentsOf: url))
    }

    private static func object(_ json: String?) throws -> [String: Any] {
        let json = try #require(json)
        return try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    private let response = OpenAIUsageResponse(
        planType: "plus",
        primary: .init(usedPercent: 42, windowSeconds: 18000, resetAt: Date(timeIntervalSince1970: 1_792_810_000)),
        secondary: nil,
        additional: [],
        credits: nil
    )

    private func makeService(
        _ usage: StubUsage,
        _ tokens: StubTokens,
        _ store: some CredentialStoring
    ) -> OpenAISubscriptionReportService {
        OpenAISubscriptionReportService(
            usage: usage,
            tokens: tokens,
            credentialStore: store,
            models: StubSessionModelStore(),
            now: { Self.renewedAt }
        )
    }

    private func fetch(_ service: OpenAISubscriptionReportService, _ json: String? = bundle()) async throws -> ProviderReport {
        try await service.fetchReport(credentials: json.map { ["auth-json": $0] } ?? [:], today: Self.today)
    }

    @Test func successNeedsNoRefresh() async throws {
        let usage = StubUsage(response: response)
        let tokens = StubTokens(grant: try Self.grant())
        let store = MemoryCredentialStore()
        store.values[Self.key] = Self.bundle()
        let service = makeService(usage, tokens, store)

        let report = try await fetch(service)

        #expect(report == OpenAIReportMapper.subscription(response, now: Self.today))
        #expect(usage.accessTokens == ["old-access"])
        #expect(tokens.refreshTokens.isEmpty)
        #expect(store.values[Self.key] == Self.bundle())
    }

    @Test func unauthorizedRefreshesStoresAndRetries() async throws {
        let usage = StubUsage(response: response)
        usage.rejected = ["old-access"]
        let tokens = StubTokens(grant: try Self.grant())
        let store = MemoryCredentialStore()
        store.values[Self.key] = Self.bundle()
        let service = makeService(usage, tokens, store)

        let report = try await fetch(service)

        #expect(report == OpenAIReportMapper.subscription(response, now: Self.today))
        #expect(tokens.refreshTokens == ["old-refresh"])
        #expect(usage.accessTokens == ["old-access", "new-access"])

        let stored = try Self.object(store.values[Self.key])
        let storedTokens = try #require(stored["tokens"] as? [String: Any])
        #expect(storedTokens["access_token"] as? String == "new-access")
        #expect(storedTokens["refresh_token"] as? String == "new-refresh")
        #expect(storedTokens["id_token"] as? String == "new-id")
        #expect(storedTokens["account_id"] as? String == "acct-file")
        #expect(stored["auth_mode"] as? String == "chatgpt")
        #expect((stored["future_field"] as? [String: Any])?["a"] as? Int == 1)
        #expect(stored["last_refresh"] as? String
            == Self.renewedAt.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
    }

    @Test func aSecondUnauthorizedIsExpired() async throws {
        let usage = StubUsage(response: response)
        usage.rejected = ["old-access", "new-access"]
        let tokens = StubTokens(grant: try Self.grant())
        let store = MemoryCredentialStore()
        store.values[Self.key] = Self.bundle()
        let service = makeService(usage, tokens, store)

        await #expect(throws: FetchError.unauthorized) {
            try await fetch(service)
        }
        #expect(tokens.refreshTokens == ["old-refresh"])
        #expect(usage.accessTokens == ["old-access", "new-access"])
    }

    @Test func forbiddenUsageIsUnauthorizedWithoutRenewing() async throws {
        let usage = StubUsage(response: response)
        usage.forbidden = ["old-access"]
        let tokens = StubTokens(grant: try Self.grant())
        let store = MemoryCredentialStore()
        store.values[Self.key] = Self.bundle()
        let service = makeService(usage, tokens, store)

        await #expect(throws: FetchError.unauthorized) {
            try await fetch(service)
        }
        #expect(tokens.refreshTokens.isEmpty)
        #expect(usage.accessTokens == ["old-access"])
        #expect(store.values[Self.key] == Self.bundle())
    }

    @Test func rejectedRefreshIsExpired() async throws {
        let usage = StubUsage(response: response)
        usage.rejected = ["old-access"]
        let tokens = StubTokens(grant: try Self.grant())
        tokens.result = .failure(.unauthorized)
        let store = MemoryCredentialStore()
        store.values[Self.key] = Self.bundle()
        let service = makeService(usage, tokens, store)

        await #expect(throws: FetchError.unauthorized) {
            try await fetch(service)
        }
        #expect(tokens.refreshTokens == ["old-refresh"])
        #expect(usage.accessTokens == ["old-access"])
        #expect(store.values[Self.key] == Self.bundle())
    }

    @Test func transientRefreshFailureIsNotExpiry() async throws {
        let usage = StubUsage(response: response)
        usage.rejected = ["old-access"]
        let tokens = StubTokens(grant: try Self.grant())
        tokens.result = .failure(.httpStatus(503))
        let store = MemoryCredentialStore()
        store.values[Self.key] = Self.bundle()
        let service = makeService(usage, tokens, store)

        await #expect(throws: FetchError.httpStatus(503)) {
            try await fetch(service)
        }
        #expect(store.values[Self.key] == Self.bundle())
    }

    @Test func overlappingRenewalsSpendTheRefreshTokenOnce() async throws {
        let usage = StubUsage(response: response)
        usage.rejected = ["old-access"]
        let tokens = StubTokens(grant: try Self.grant())
        let gate = RenewalGate()
        tokens.gate = gate
        let store = MemoryCredentialStore()
        store.values[Self.key] = Self.bundle()
        let service = makeService(usage, tokens, store)

        let scheduled = Task { try await fetch(service) }
        let manual = Task { try await fetch(service) }
        await gate.waitUntilStarted()
        await settle()

        // Both fetches got 401 before the renewal finished.
        #expect(usage.accessTokens == ["old-access", "old-access"])
        gate.open()

        let expected = OpenAIReportMapper.subscription(response, now: Self.today)
        #expect(try await scheduled.value == expected)
        #expect(try await manual.value == expected)
        #expect(tokens.refreshTokens == ["old-refresh"])
        #expect(usage.accessTokens == ["old-access", "old-access", "new-access", "new-access"])
        #expect(try CodexAuth(json: try #require(store.values[Self.key])).refreshToken == "new-refresh")
    }

    @Test func aNewerStoredTokenIsUsedWithoutRefreshing() async throws {
        let usage = StubUsage(response: response)
        usage.rejected = ["old-access"]
        let tokens = StubTokens(grant: try Self.grant())
        let store = MemoryCredentialStore()
        let newer = Self.bundle(access: "newer-access", refresh: "newer-refresh")
        store.values[Self.key] = newer
        let service = makeService(usage, tokens, store)

        let report = try await fetch(service)

        #expect(report == OpenAIReportMapper.subscription(response, now: Self.today))
        #expect(tokens.refreshTokens.isEmpty)
        #expect(usage.accessTokens == ["old-access", "newer-access"])
        #expect(store.values[Self.key] == newer)
    }

    @Test func aRePasteDuringRenewalIsNotOverwritten() async throws {
        let usage = StubUsage(response: response)
        usage.rejected = ["old-access"]
        let tokens = StubTokens(grant: try Self.grant())
        let store = MemoryCredentialStore()
        store.values[Self.key] = Self.bundle()
        let pasted = Self.bundle(access: "pasted-access", refresh: "pasted-refresh")
        tokens.whileRenewing = { store.values[Self.key] = pasted }
        let service = makeService(usage, tokens, store)

        let report = try await fetch(service)

        #expect(report == OpenAIReportMapper.subscription(response, now: Self.today))
        #expect(tokens.refreshTokens == ["old-refresh"])
        #expect(usage.accessTokens == ["old-access", "pasted-access"])
        #expect(store.values[Self.key] == pasted)
    }

    @Test func aFailedWriteKeepsTheRenewedBundleInMemory() async throws {
        let usage = StubUsage(response: response)
        usage.rejected = ["old-access"]
        let tokens = StubTokens(grant: try Self.grant())
        let store = FailingCredentialStore()
        store.base.values[Self.key] = Self.bundle()
        store.failsWrites = true
        let service = makeService(usage, tokens, store)

        _ = try await fetch(service)
        #expect(store.base.values[Self.key] == Self.bundle())

        // The caller still reads the spent bundle from Keychain.
        _ = try await fetch(service)
        #expect(tokens.refreshTokens == ["old-refresh"])
        #expect(usage.accessTokens == ["old-access", "new-access", "new-access"])
        #expect(store.base.values[Self.key] == Self.bundle())

        store.failsWrites = false
        _ = try await fetch(service)

        let saved = try CodexAuth(json: try #require(store.base.values[Self.key]))
        #expect(saved.accessToken == "new-access")
        #expect(saved.refreshToken == "new-refresh")
        #expect(usage.accessTokens.last == "new-access")
        #expect(tokens.refreshTokens == ["old-refresh"])
    }

    @Test func anUnreadableKeychainAfterTheGrantStillSavesIt() async throws {
        let usage = StubUsage(response: response)
        usage.rejected = ["old-access"]
        let tokens = StubTokens(grant: try Self.grant())
        let store = FailingCredentialStore()
        store.base.values[Self.key] = Self.bundle()
        tokens.whileRenewing = { store.secretReadError = FailingCredentialStore.Failure() }
        let service = makeService(usage, tokens, store)

        _ = try await fetch(service)

        let saved = try CodexAuth(json: try #require(store.base.values[Self.key]))
        #expect(saved.accessToken == "new-access")
        #expect(saved.refreshToken == "new-refresh")
        #expect(usage.accessTokens == ["old-access", "new-access"])
    }

    @Test func anUnreadableAndUnwritableKeychainAfterTheGrantKeepsItInMemory() async throws {
        let usage = StubUsage(response: response)
        usage.rejected = ["old-access"]
        let tokens = StubTokens(grant: try Self.grant())
        let store = FailingCredentialStore()
        store.base.values[Self.key] = Self.bundle()
        tokens.whileRenewing = {
            store.secretReadError = FailingCredentialStore.Failure()
            store.failsWrites = true
        }
        let service = makeService(usage, tokens, store)

        _ = try await fetch(service)
        #expect(store.base.values[Self.key] == Self.bundle())

        store.secretReadError = nil
        _ = try await fetch(service)

        #expect(tokens.refreshTokens == ["old-refresh"])
        #expect(usage.accessTokens == ["old-access", "new-access", "new-access"])
    }

    @Test(arguments: [nil, "not json"] as [String?])
    func anEmptyOrBrokenKeychainBeforeRenewingIsUnauthorized(stored: String?) async throws {
        let usage = StubUsage(response: response)
        usage.rejected = ["old-access"]
        let tokens = StubTokens(grant: try Self.grant())
        let store = MemoryCredentialStore()
        store.values[Self.key] = stored
        let service = makeService(usage, tokens, store)

        await #expect(throws: FetchError.unauthorized) {
            try await fetch(service)
        }
        #expect(tokens.refreshTokens.isEmpty)
        #expect(store.values[Self.key] == stored)
    }

    @Test func anUnreadableKeychainAtFetchStartKeepsTheUnsavedBundle() async throws {
        let usage = StubUsage(response: response)
        usage.rejected = ["old-access"]
        let tokens = StubTokens(grant: try Self.grant())
        let store = FailingCredentialStore()
        store.base.values[Self.key] = Self.bundle()
        store.failsWrites = true
        let service = makeService(usage, tokens, store)
        _ = try await fetch(service)

        store.secretReadError = FailingCredentialStore.Failure()
        store.failsWrites = false
        _ = try await fetch(service)

        #expect(usage.accessTokens == ["old-access", "new-access", "new-access"])
        #expect(store.base.values[Self.key] == Self.bundle())

        store.secretReadError = nil
        _ = try await fetch(service)

        let saved = try CodexAuth(json: try #require(store.base.values[Self.key]))
        #expect(saved.accessToken == "new-access")
        #expect(tokens.refreshTokens == ["old-refresh"])
    }

    @Test func aRePasteDropsTheUnsavedBundle() async throws {
        let usage = StubUsage(response: response)
        usage.rejected = ["old-access"]
        let tokens = StubTokens(grant: try Self.grant())
        let store = FailingCredentialStore()
        store.base.values[Self.key] = Self.bundle()
        store.failsWrites = true
        let service = makeService(usage, tokens, store)
        _ = try await fetch(service)

        let pasted = Self.bundle(access: "pasted-access", refresh: "pasted-refresh")
        store.base.values[Self.key] = pasted
        store.failsWrites = false
        _ = try await fetch(service, pasted)

        #expect(usage.accessTokens == ["old-access", "new-access", "pasted-access"])
        #expect(store.base.values[Self.key] == pasted)
    }

    @Test func anUnsavedBundleRenewsWithItsOwnRefreshToken() async throws {
        let usage = StubUsage(response: response)
        usage.rejected = ["old-access"]
        let tokens = StubTokens(grant: try Self.grant())
        let store = FailingCredentialStore()
        store.base.values[Self.key] = Self.bundle()
        store.failsWrites = true
        let service = makeService(usage, tokens, store)
        _ = try await fetch(service)

        // The unsaved bundle expires too; Keychain still holds the spent one.
        usage.rejected = ["old-access", "new-access"]
        tokens.result = .success(CodexTokenGrant(idToken: nil, accessToken: "newest-access", refreshToken: "newest-refresh"))
        _ = try await fetch(service)

        #expect(tokens.refreshTokens == ["old-refresh", "new-refresh"])
        #expect(usage.accessTokens == ["old-access", "new-access", "new-access", "newest-access"])
        #expect(store.base.values[Self.key] == Self.bundle())

        store.failsWrites = false
        _ = try await fetch(service)

        #expect(usage.accessTokens.last == "newest-access")
        let saved = try CodexAuth(json: try #require(store.base.values[Self.key]))
        #expect(saved.accessToken == "newest-access")
        #expect(saved.refreshToken == "newest-refresh")
    }

    @Test func missingCredentialIsUnauthorized() async throws {
        let usage = StubUsage(response: response)
        let tokens = StubTokens(grant: try Self.grant())
        let service = makeService(usage, tokens, MemoryCredentialStore())

        await #expect(throws: FetchError.unauthorized) {
            try await fetch(service, nil)
        }
        #expect(usage.accessTokens.isEmpty)
        #expect(tokens.refreshTokens.isEmpty)
    }

    // MARK: Starting a session

    private func start(_ service: OpenAISubscriptionReportService, _ json: String? = bundle()) async throws {
        try await service.startSession(credentials: json.map { ["auth-json": $0] } ?? [:])
    }

    @Test func aStartSendsTheSessionModel() async throws {
        let usage = StubUsage(response: response)
        let tokens = StubTokens(grant: try Self.grant())
        let store = MemoryCredentialStore()
        store.values[Self.key] = Self.bundle()
        let service = makeService(usage, tokens, store)

        try await start(service)

        #expect(usage.starts.map(\.accessToken) == ["old-access"])
        #expect(usage.starts.map(\.model) == ["test-model"])
        #expect(usage.accessTokens.isEmpty)
        #expect(tokens.refreshTokens.isEmpty)
    }

    @Test func aRefusedStartThrows() async throws {
        let usage = StubUsage(response: response)
        usage.startError = .httpStatus(400)
        let tokens = StubTokens(grant: try Self.grant())
        let store = MemoryCredentialStore()
        store.values[Self.key] = Self.bundle()
        let service = makeService(usage, tokens, store)

        await #expect(throws: FetchError.httpStatus(400)) {
            try await start(service)
        }
        #expect(usage.starts.map(\.accessToken) == ["old-access"])
        #expect(tokens.refreshTokens.isEmpty)
        #expect(store.values[Self.key] == Self.bundle())
    }

    @Test func anExpiredTokenIsRenewedOnceThenTheStartRetried() async throws {
        let usage = StubUsage(response: response)
        usage.rejected = ["old-access"]
        let tokens = StubTokens(grant: try Self.grant())
        let store = MemoryCredentialStore()
        store.values[Self.key] = Self.bundle()
        let service = makeService(usage, tokens, store)

        try await start(service)

        #expect(tokens.refreshTokens == ["old-refresh"])
        #expect(usage.starts.map(\.accessToken) == ["old-access", "new-access"])
        #expect(try CodexAuth(json: try #require(store.values[Self.key])).refreshToken == "new-refresh")
    }

    @Test func aStartStillExpiredAfterRenewingIsUnauthorized() async throws {
        let usage = StubUsage(response: response)
        usage.rejected = ["old-access", "new-access"]
        let tokens = StubTokens(grant: try Self.grant())
        let store = MemoryCredentialStore()
        store.values[Self.key] = Self.bundle()
        let service = makeService(usage, tokens, store)

        await #expect(throws: FetchError.unauthorized) {
            try await start(service)
        }
        #expect(tokens.refreshTokens == ["old-refresh"])
        #expect(usage.starts.map(\.accessToken) == ["old-access", "new-access"])
    }

    @Test func aStartAndAFetchShareOneRenewal() async throws {
        let usage = StubUsage(response: response)
        usage.rejected = ["old-access"]
        let tokens = StubTokens(grant: try Self.grant())
        let gate = RenewalGate()
        tokens.gate = gate
        let store = MemoryCredentialStore()
        store.values[Self.key] = Self.bundle()
        let service = makeService(usage, tokens, store)

        let fetching = Task { try await fetch(service) }
        let starting = Task { try await start(service) }
        await gate.waitUntilStarted()
        await settle()

        // Both got 401 before the renewal finished.
        #expect(usage.accessTokens == ["old-access"])
        #expect(usage.starts.map(\.accessToken) == ["old-access"])
        gate.open()

        #expect(try await fetching.value == OpenAIReportMapper.subscription(response, now: Self.today))
        try await starting.value
        #expect(tokens.refreshTokens == ["old-refresh"])
        #expect(usage.accessTokens == ["old-access", "new-access"])
        #expect(usage.starts.map(\.accessToken) == ["old-access", "new-access"])
        #expect(try CodexAuth(json: try #require(store.values[Self.key])).refreshToken == "new-refresh")
    }

    @Test func aStartUsesTheUnsavedBundle() async throws {
        let usage = StubUsage(response: response)
        usage.rejected = ["old-access"]
        let tokens = StubTokens(grant: try Self.grant())
        let store = FailingCredentialStore()
        store.base.values[Self.key] = Self.bundle()
        store.failsWrites = true
        let service = makeService(usage, tokens, store)
        _ = try await fetch(service)

        // The caller still reads the spent bundle from Keychain.
        try await start(service)

        #expect(usage.starts.map(\.accessToken) == ["new-access"])
        #expect(tokens.refreshTokens == ["old-refresh"])
    }

    @Test func aStartWithoutACredentialIsUnauthorized() async throws {
        let usage = StubUsage(response: response)
        let tokens = StubTokens(grant: try Self.grant())
        let service = makeService(usage, tokens, MemoryCredentialStore())

        await #expect(throws: FetchError.unauthorized) {
            try await start(service, nil)
        }
        #expect(usage.starts.isEmpty)
        #expect(tokens.refreshTokens.isEmpty)
    }
}
