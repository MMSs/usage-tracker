import Foundation
import os

enum HalfStatus: Equatable, Sendable {
    case unconfigured, loading, ready, error, expired
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

    private let provider: Provider
    private let credentialFieldIDs: [String]
    private let fetcher: ReportFetching
    private let credentialStore: CredentialStoring
    private let cache: ReportCaching
    private let now: () -> Date
    private var refreshGeneration = 0

    var isConfigured: Bool { status != .unconfigured }

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
            Log.refresh.debug("\(name, privacy: .public): skipped, blocked until the credential is replaced")
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

            let date = now()
            report = fetched
            lastSuccess = date
            isStale = false
            scheduledRetriesBlocked = false
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
                status = switch lastFailure?.cause {
                case .unauthorized: .expired
                case .some: .error
                case nil: statusBefore
                }
            }
            return
        } catch {
            guard generation == refreshGeneration else {
                Log.refresh.debug("\(name, privacy: .public): superseded failure discarded")
                return
            }

            let cause = RefreshFailure(error)
            if cause == .unexpected {
                // The type name only: an error's description could quote a response.
                Log.refresh.error("\(name, privacy: .public): unexpected \(String(describing: type(of: error)), privacy: .public)")
            }
            fail(cause)
        }
    }

    /// The service's `Retry-After` from the last failure, when it was a 429
    /// that gave one; scheduled refreshes wait for it, manual ones do not.
    private var rateLimitedUntil: Date? {
        guard case let .rateLimited(until)? = lastFailure?.cause else {
            return nil
        }

        return until
    }

    /// Called after Settings saved or removed a credential for this half.
    func credentialsChanged() async {
        // Invalidates any fetch still in flight for the old credentials.
        Log.refresh.debug("\(self.logName, privacy: .public): credential changed")
        refreshGeneration += 1
        scheduledRetriesBlocked = false
        await refresh(manual: true)
    }

    private func fail(_ cause: RefreshFailure) {
        lastFailure = RecordedFailure(cause: cause, date: now())
        let name = logName

        if cause == .unauthorized {
            status = .expired
            scheduledRetriesBlocked = true
            Log.refresh.error("\(name, privacy: .public): failed (unauthorized); expired, scheduled refreshes blocked")
        } else {
            status = .error
            Log.refresh.error("\(name, privacy: .public): failed (\(cause.description, privacy: .public))")
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
