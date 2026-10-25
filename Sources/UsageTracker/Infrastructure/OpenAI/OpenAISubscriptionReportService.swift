import Foundation

@MainActor
final class OpenAISubscriptionReportService: ReportFetching, SessionStarting {
    private static let provider = Provider.openai
    private static let key = CredentialKey(provider: provider, fieldID: "auth-json")

    private let usage: OpenAIUsageFetching
    private let tokens: OpenAITokenRenewing
    private let credentialStore: CredentialStoring
    private let models: SessionModelStoring
    private let now: () -> Date
    /// Shared by overlapping fetches: the refresh token is single-use. A
    /// task of its own, so a cancelled fetch cannot abandon a spent token.
    private var renewalTask: Task<CodexAuth, Error>?
    /// A renewed bundle Keychain refused, and the spent refresh token Keychain
    /// still holds in its place. Its refresh token is the only live one.
    private var pending: (json: String, replacing: String)?

    init(
        usage: OpenAIUsageFetching,
        tokens: OpenAITokenRenewing,
        credentialStore: CredentialStoring,
        models: SessionModelStoring,
        now: @escaping () -> Date = Date.init
    ) {
        self.usage = usage
        self.tokens = tokens
        self.credentialStore = credentialStore
        self.models = models
        self.now = now
    }

    func fetchReport(credentials: [String: String], today: Date) async throws -> ProviderReport {
        let response = try await withRenewal(try authJSON(credentials)) { auth in
            try await usage.fetchUsage(auth: auth)
        }

        return OpenAIReportMapper.subscription(response, now: today)
    }

    func startSession(credentials: [String: String]) async throws {
        let model = models.model(for: Self.provider)

        try await withRenewal(try authJSON(credentials)) { auth in
            try await usage.startSession(auth: auth, model: model)
        }
    }

    /// The bundle to use: the pending one while Keychain still refuses it,
    /// else the caller's.
    private func authJSON(_ credentials: [String: String]) throws -> String {
        retryPendingSave()

        guard let json = pending?.json ?? credentials["auth-json"] else {
            throw FetchError.unauthorized
        }

        return json
    }

    /// Runs `body`, and once more with a renewed token when it reports the
    /// access token expired. A second expiry is `FetchError.unauthorized`.
    private func withRenewal<T>(_ json: String, _ body: (CodexAuth) async throws -> T) async throws -> T {
        let auth = try CodexAuth(json: json)
        do {
            return try await body(auth)
        } catch OpenAIUsageError.accessTokenExpired {
            let renewed = try await renewal(after: auth)
            do {
                return try await body(renewed)
            } catch OpenAIUsageError.accessTokenExpired {
                throw FetchError.unauthorized
            }
        }
    }

    private func renewal(after failed: CodexAuth) async throws -> CodexAuth {
        if let renewalTask {
            return try await renewalTask.value
        }

        let task = Task {
            defer { renewalTask = nil }
            return try await renew(after: failed)
        }
        renewalTask = task

        return try await task.value
    }

    private func renew(after failed: CodexAuth) async throws -> CodexAuth {
        guard let stored = try storedJSON(), let storedAuth = try? CodexAuth(json: stored) else {
            throw FetchError.unauthorized
        }

        // An earlier renewal or a re-paste already replaced the token that failed.
        guard storedAuth.accessToken == failed.accessToken else {
            return storedAuth
        }

        let grant = try await tokens.renew(refreshToken: failed.refreshToken)
        let renewedJSON = try CodexAuth.renewedJSON(stored, grant: grant, at: now())
        let renewed = try CodexAuth(json: renewedJSON)

        // The user may have re-pasted or removed the bundle while it renewed; theirs wins.
        let current: String?
        do {
            current = try storedJSON()
        } catch {
            current = stored
        }

        guard let current, let currentAuth = try? CodexAuth(json: current) else {
            throw FetchError.unauthorized
        }

        guard currentAuth.refreshToken == failed.refreshToken else {
            return currentAuth
        }

        save(renewedJSON, replacing: pending?.replacing ?? failed.refreshToken)

        return renewed
    }

    /// Keychain's bundle, or the pending one while Keychain still holds the
    /// refresh token it replaced. Forgets the pending one once Keychain holds
    /// anything else: the user re-pasted or removed it.
    private func storedJSON() throws -> String? {
        let stored = try credentialStore.credential(for: Self.key)

        if let pending {
            if let stored, (try? CodexAuth(json: stored))?.refreshToken == pending.replacing {
                return pending.json
            }
            self.pending = nil
        }

        return stored
    }

    private func retryPendingSave() {
        guard let pending else {
            return
        }

        // An unreadable Keychain keeps the bundle for the next fetch; one
        // holding anything else has already dropped it.
        guard (try? storedJSON()) == pending.json else {
            return
        }

        save(pending.json, replacing: pending.replacing)
    }

    private func save(_ json: String, replacing refreshToken: String) {
        do {
            try credentialStore.set(json, for: Self.key)
            pending = nil
        } catch {
            Log.refresh.error("openai subscription: renewed token not saved")
            pending = (json, refreshToken)
        }
    }
}
