import Foundation

@MainActor
final class OpenAISubscriptionReportService: ReportFetching {
    private static let key = CredentialKey(provider: .openai, fieldID: "auth-json")

    private let usage: OpenAIUsageFetching
    private let tokens: OpenAITokenRenewing
    private let credentialStore: CredentialStoring
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
        now: @escaping () -> Date = Date.init
    ) {
        self.usage = usage
        self.tokens = tokens
        self.credentialStore = credentialStore
        self.now = now
    }

    func fetchReport(credentials: [String: String], today: Date) async throws -> ProviderReport {
        retryPendingSave()

        guard let json = pending?.json ?? credentials["auth-json"] else {
            throw FetchError.unauthorized
        }

        let auth = try CodexAuth(json: json)
        let response: OpenAIUsageResponse
        do {
            response = try await usage.fetchUsage(auth: auth)
        } catch FetchError.unauthorized {
            let renewed = try await renewal(after: auth)
            response = try await usage.fetchUsage(auth: renewed)
        }

        return OpenAIReportMapper.subscription(response, now: today)
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
