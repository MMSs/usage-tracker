import Foundation
import os

enum HalfStatus: Equatable, Sendable {
    case unconfigured, loading, ready, error, expired
    /// The credential sees several organizations and none is chosen; nothing
    /// is fetched until the user picks one.
    case needsOrganization
}

/// One independently fetched half (subscription or API spend) of a provider.
@MainActor
final class HalfViewModel: ObservableObject {
    let half: Half
    @Published private(set) var status: HalfStatus = .unconfigured
    @Published private(set) var report: ProviderReport?
    @Published private(set) var lastSuccess: Date?
    /// Why the last refresh failed; nil after a success.
    @Published private(set) var lastFailure: RecordedFailure?
    /// False after the first success this run.
    @Published private(set) var isStale: Bool = true
    /// Off: nothing drawn, nothing fetched; the credential and last report are kept.
    @Published var isEnabled = true
    private(set) var scheduledRetriesBlocked = false
    /// The last 429's `Retry-After`: scheduled refreshes wait for it, manual
    /// ones do not. Only a success or a newer 429 changes it; another failure
    /// meanwhile has not said the limit lifted.
    private(set) var rateLimitedUntil: Date?
    /// The organizations the fetcher can report on, when it is scoped to one;
    /// empty otherwise or before the first listing.
    @Published private(set) var organizations: [AccountOrganization] = []
    /// The stored choice, which may no longer be listed; see `chosenOrganization`.
    @Published private(set) var selectedOrganizationID: String?
    /// Progress of the last "start the session" request.
    @Published private(set) var sessionStart: SessionStartState = .idle
    /// When a start was last attempted, from the button or automatically,
    /// failed or not; the automatic start waits on it.
    private(set) var lastSessionStartAttempt: Date?

    private let provider: Provider
    private let credentialFieldIDs: [String]
    private let fetcher: ReportFetching
    private let credentialStore: CredentialStoring
    private let cache: ReportCaching
    private let now: () -> Date
    private var refreshGeneration = 0

    var isConfigured: Bool { status != .unconfigured }

    /// True when the credential sees more than one organization, so Settings offers the choice.
    var offersOrganizationChoice: Bool { organizations.count > 1 }

    /// The chosen organization while it is still listed.
    var chosenOrganization: AccountOrganization? {
        organizations.first { $0.id == selectedOrganizationID }
    }

    private var organizationScope: OrganizationScopedFetching? {
        fetcher as? OrganizationScopedFetching
    }

    private var sessionStarter: SessionStarting? {
        fetcher as? SessionStarting
    }

    /// True when the fetcher can open its provider's session.
    var canStartSession: Bool { sessionStarter != nil }

    init(
        provider: Provider,
        half: Half,
        fields: [CredentialField],
        fetcher: ReportFetching,
        credentialStore: CredentialStoring,
        cache: ReportCaching,
        now: @escaping () -> Date = Date.init
    ) {
        self.provider = provider
        self.half = half
        // The budget is a plain setting, not a credential.
        self.credentialFieldIDs = fields.map(\.id).filter { $0 != "api-budget" }
        self.fetcher = fetcher
        self.credentialStore = credentialStore
        self.cache = cache
        self.now = now
        selectedOrganizationID = organizationScope?.selectedOrganizationID

        let values: [String: String]
        do {
            values = try readValues()
        } catch {
            // A failing store must not hide the last successful report.
            loadCached()
            fail(.keychain)
            return
        }

        guard isConfigured(values) else {
            cache.clear(provider: provider, half: half)
            // A choice made for a credential that is gone means nothing now.
            organizationScope?.resetOrganizations()
            selectedOrganizationID = nil
            return
        }

        loadCached()
        status = .loading
    }

    /// Enabled and holding a credential: the half takes part in the item and the popover.
    var isActive: Bool { isEnabled && isConfigured }

    func refresh(manual: Bool) async {
        let name = logName
        guard isEnabled else {
            Log.refresh.debug("\(name, privacy: .public): skipped, switched off")
            return
        }

        if !manual, scheduledRetriesBlocked {
            let until = status == .needsOrganization ? "an organization is chosen" : "the credential is replaced"
            Log.refresh.debug("\(name, privacy: .public): skipped, blocked until \(until, privacy: .public)")
            return
        }

        if !manual, let until = rateLimitedUntil, now() < until {
            Log.refresh.debug("\(name, privacy: .public): skipped, rate limited until \(until.ISO8601Format(), privacy: .public)")
            return
        }

        refreshGeneration += 1
        let generation = refreshGeneration
        Log.refresh.debug("\(name, privacy: .public): refresh started (\(manual ? "manual" : "scheduled", privacy: .public))")

        let values: [String: String]
        do {
            values = try readValues()
        } catch {
            fail(.keychain)
            return
        }

        guard isConfigured(values) else {
            Log.refresh.debug("\(name, privacy: .public): no credential")
            markUnconfigured()
            return
        }

        let statusBefore = status
        if report == nil {
            status = .loading
        }

        do {
            let fetched = try await fetcher.fetchReport(credentials: values, today: now())
            guard generation == refreshGeneration else {
                Log.refresh.debug("\(name, privacy: .public): superseded result discarded")
                return
            }

            syncOrganizations()
            let date = now()
            report = fetched
            lastSuccess = date
            isStale = false
            scheduledRetriesBlocked = false
            rateLimitedUntil = nil
            lastFailure = nil
            status = .ready
            cache.store(CachedReport(report: fetched, fetchedAt: date), provider: provider, half: half)
            Log.refresh.info("\(name, privacy: .public): refreshed")
        } catch is CancellationError {
            // Cancelled, not failed: a half with no report must not sit on
            // "Loading…" hiding its error. The last failure decides, not the
            // status this refresh began from: an overlapping refresh whose
            // result was superseded may have left that on "Loading…" too.
            Log.refresh.debug("\(name, privacy: .public): refresh cancelled")
            if generation == refreshGeneration, report == nil, status == .loading {
                status = lastFailure.map { Self.status(for: $0.cause) } ?? statusBefore
            }
            return
        } catch {
            guard generation == refreshGeneration else {
                Log.refresh.debug("\(name, privacy: .public): superseded failure discarded")
                return
            }

            syncOrganizations()
            let cause = RefreshFailure(error)
            if cause == .unexpected {
                // The type name only: an error's description could quote a response.
                Log.refresh.error("\(name, privacy: .public): unexpected \(String(describing: type(of: error)), privacy: .public)")
            }
            fail(cause)
        }
    }

    /// Sends the provider's session-starting message, then refreshes so the
    /// new window shows. False when it cannot start, is switched off, one is
    /// already running, or it failed (`sessionStart` is then `.failed`).
    @discardableResult
    func startSession() async -> Bool {
        guard isEnabled, let starter = sessionStarter, sessionStart != .starting else {
            return false
        }

        let name = logName
        sessionStart = .starting
        lastSessionStartAttempt = now()
        do {
            let values = try readValues()
            guard isConfigured(values) else {
                Log.refresh.debug("\(name, privacy: .public): session start skipped, no credential")
                sessionStart = .failed
                return false
            }

            try await starter.startSession(credentials: values)
        } catch is CancellationError {
            Log.refresh.debug("\(name, privacy: .public): session start cancelled")
            sessionStart = .idle
            return false
        } catch {
            // The type name only: an error's description could quote a response.
            Log.refresh.error("\(name, privacy: .public): session start failed \(String(describing: type(of: error)), privacy: .public)")
            sessionStart = .failed
            return false
        }

        Log.refresh.info("\(name, privacy: .public): session started")
        sessionStart = .idle
        await refresh(manual: true)
        return true
    }

    /// Called after Settings saved or removed a credential for this half.
    func credentialsChanged() async {
        // Invalidates any fetch still in flight for the old credentials.
        Log.refresh.debug("\(self.logName, privacy: .public): credential changed")
        refreshGeneration += 1
        scheduledRetriesBlocked = false
        // A 429 wait was earned by the old credential or organization.
        rateLimitedUntil = nil
        if let scope = organizationScope {
            // The choice belonged to the old credential's account.
            scope.resetOrganizations()
            syncOrganizations()
            Log.refresh.debug("\(self.logName, privacy: .public): organization choice cleared")
        }
        await refresh(manual: true)
    }

    /// Stores the user's organization choice and refreshes with it now. Does
    /// nothing when the fetcher is not scoped to an organization.
    func selectOrganization(_ id: String) async {
        guard let scope = organizationScope else {
            return
        }

        scope.selectOrganization(id)
        selectedOrganizationID = id
        Log.refresh.info("\(self.logName, privacy: .public): organization chosen from \(self.organizations.count, privacy: .public) listed")
        // Invalidates any fetch still in flight for the previous choice.
        refreshGeneration += 1
        scheduledRetriesBlocked = false
        await refresh(manual: true)
    }

    private static func status(for cause: RefreshFailure) -> HalfStatus {
        switch cause {
        case .unauthorized: .expired
        case .needsOrganization: .needsOrganization
        default: .error
        }
    }

    private func fail(_ cause: RefreshFailure) {
        lastFailure = RecordedFailure(cause: cause, date: now())
        if case let .rateLimited(until) = cause {
            rateLimitedUntil = until
        }
        status = Self.status(for: cause)
        let name = logName

        switch cause {
        case .unauthorized:
            scheduledRetriesBlocked = true
            Log.refresh.error("\(name, privacy: .public): failed (unauthorized); expired, scheduled refreshes blocked")
        case .needsOrganization:
            // Nothing changes until the user chooses, so the timer would only list them again.
            scheduledRetriesBlocked = true
            // What is kept may be another organization's: drop it, in memory and cached.
            report = nil
            lastSuccess = nil
            cache.clear(provider: provider, half: half)
            Log.refresh.notice("\(name, privacy: .public): several organizations, none chosen; scheduled refreshes wait for a choice")
        default:
            // This failure replaces a block (an expired credential, a wait for
            // a choice), and its row says it retries: let the schedule ask
            // again. It succeeds, or hits the same wall and blocks again.
            scheduledRetriesBlocked = false
            Log.refresh.error("\(name, privacy: .public): failed (\(cause.description, privacy: .public))")
        }
    }

    /// Copies the scoped fetcher's organizations and choice for the views.
    private func syncOrganizations() {
        guard let scope = organizationScope else {
            return
        }

        if organizations != scope.organizations {
            organizations = scope.organizations
        }
        if selectedOrganizationID != scope.selectedOrganizationID {
            selectedOrganizationID = scope.selectedOrganizationID
        }
    }

    /// "anthropic api": names the half in log lines.
    private var logName: String {
        "\(provider.rawValue) \(half.rawValue)"
    }

    private func loadCached() {
        if let cached = cache.cached(provider: provider, half: half) {
            report = cached.report
            lastSuccess = cached.fetchedAt
        }
    }

    /// Configured means every credential field (not the budget setting) has a value.
    private func isConfigured(_ values: [String: String]) -> Bool {
        !credentialFieldIDs.isEmpty && values.count == credentialFieldIDs.count
    }

    private func markUnconfigured() {
        status = .unconfigured
        report = nil
        lastSuccess = nil
        lastFailure = nil
        scheduledRetriesBlocked = false
        rateLimitedUntil = nil
        organizations = []
        cache.clear(provider: provider, half: half)
    }

    /// Non-blank values keyed by field id; throws if the store cannot be read.
    private func readValues() throws -> [String: String] {
        var values: [String: String] = [:]
        for id in credentialFieldIDs {
            let value = try credentialStore.credential(for: CredentialKey(provider: provider, fieldID: id))
            if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                values[id] = value
            }
        }
        return values
    }
}
