import Foundation
import os

/// What the app does with what arrives from the other Macs, and what it
/// gives them. The app model implements it.
@MainActor
protocol SyncApplying: AnyObject {
    /// Every shared setting as this Mac has it, for iCloud to start from.
    func syncedSettings() -> [SyncedSetting]
    /// Applies another Mac's setting without sending it back.
    func applySynced(_ setting: SyncedSetting)
    /// The half's latest outcome; nil when it has none or the provider lacks the half.
    func sharedState(for target: RefreshTarget) -> SharedHalfState?
    /// Takes another Mac's outcome for the half, as if refreshed here.
    func adoptShared(_ state: SharedHalfState, for target: RefreshTarget)
    func historySamples(for provider: Provider) -> [String: [UsageSample]]
    func mergeHistory(_ samples: [String: [UsageSample]], for provider: Provider)
    func selectedOrganization(for provider: Provider) -> String?
    func adoptOrganization(_ id: String?, for provider: Provider)
    /// The credentials under this Mac changed: sharing started or stopped.
    func syncedCredentialsChanged()
}

enum SyncStatus: Equatable, Sendable {
    case off
    /// Sync can't run: the build, the account, or Keychain says why.
    case unavailable(String)
    case syncing
    case upToDate(Date)
    case failed(String)
}

enum SyncFetchDecision: Equatable, Sendable {
    /// Ask the provider: no Mac has a fresh answer and this one holds the turn.
    case fetch
    /// Another Mac's answer is fresh, or that Mac is fetching now.
    case skip
}

/// Keeps this Mac in step with the user's other Macs through their private
/// iCloud: shared settings, and in Everything one fetch per refresh for all
/// of them, one session start, and one history.
@MainActor
final class SyncCoordinator: ObservableObject {
    @Published private(set) var mode: SyncMode
    @Published private(set) var status: SyncStatus = .off
    weak var delegate: SyncApplying?

    /// How long a Mac may hold a half's fetch turn before another takes over.
    static let leaseDuration: TimeInterval = 60
    /// Another Mac's answer younger than this share of the interval is used as is.
    static let freshness = 0.9
    /// Compare-and-swap saves give up after this many conflicts in a row.
    static let maxAttempts = 3

    private let transport: SyncTransport?
    private let credentials: SyncingCredentialStore?
    private let preferences: SyncPreferencesStoring
    private let credentialKeys: [CredentialKey]
    private let now: () -> Date
    /// The server's records as last seen, for their versions.
    private var records: [String: SyncRecord] = [:]
    /// Settings saved here that have not reached iCloud yet.
    private var pendingSettings: [String: SyncedSetting] = [:]
    /// True while another Mac's change is applied, so it is not sent back.
    private var applyingRemote = false
    private var pullTask: Task<Void, Never>?
    private var isStarted = false

    /// `transport` nil: this build has no iCloud entitlement. `credentials`
    /// nil: it has no keychain sharing, so Everything is unavailable.
    init(
        transport: SyncTransport?,
        credentials: SyncingCredentialStore?,
        preferences: SyncPreferencesStoring,
        credentialKeys: [CredentialKey] = IdentifierMigration.credentialKeys,
        now: @escaping () -> Date = Date.init
    ) {
        self.transport = transport
        self.credentials = credentials
        self.preferences = preferences
        self.credentialKeys = credentialKeys
        self.now = now

        var mode = preferences.mode
        if !Self.isAllowed(mode, transport: transport, credentials: credentials) {
            mode = .off
            preferences.mode = .off
        }
        self.mode = mode

        // Before any credential is read, so the providers start from the shared items.
        if mode.sharesCredentials {
            credentials?.resumeSharing()
        }
    }

    var deviceID: String { preferences.deviceID }

    func isAvailable(_ mode: SyncMode) -> Bool {
        Self.isAllowed(mode, transport: transport, credentials: credentials)
    }

    /// Why a mode can't be chosen in this build; nil when it can.
    func unavailableReason(_ mode: SyncMode) -> String? {
        guard !isAvailable(mode) else {
            return nil
        }

        return transport == nil
            ? "This copy of Usage Tracker can't use iCloud. Builds made from source don't sync."
            : "This copy of Usage Tracker can't use iCloud Keychain, so credentials can't be shared."
    }

    private static func isAllowed(_ mode: SyncMode, transport: SyncTransport?, credentials: SyncingCredentialStore?) -> Bool {
        switch mode {
        case .off: true
        case .settingsOnly: transport != nil
        case .everything: transport != nil && credentials != nil
        }
    }

    // MARK: Lifecycle

    /// Connects and catches up; idempotent.
    func start() async {
        guard !isStarted else {
            return
        }

        isStarted = true
        guard mode != .off else {
            status = .off
            return
        }

        guard await connect() else {
            return
        }

        await pull()
    }

    /// Switches mode. Joining takes what iCloud already holds over this
    /// Mac's own and uploads what iCloud lacks; leaving keeps local copies.
    func setMode(_ new: SyncMode) async {
        guard new != mode, isAvailable(new) else {
            return
        }

        let old = mode
        mode = new
        preferences.mode = new
        Log.sync.notice("mode \(old.rawValue, privacy: .public) → \(new.rawValue, privacy: .public)")

        if old.sharesCredentials, !new.sharesCredentials {
            do {
                try credentials?.stopSharing(keys: credentialKeys)
            } catch {
                Log.sync.error("keeping shared credentials failed: \(String(describing: type(of: error)), privacy: .public)")
            }
            delegate?.syncedCredentialsChanged()
        }

        guard new != .off else {
            records = [:]
            pendingSettings = [:]
            status = .off
            return
        }

        guard await connect(), let transport else {
            return
        }

        do {
            transport.resetChanges()
            let changes = try await transport.changes()
            apply(changes, joining: true)
            try await uploadMissingSettings()

            if new.sharesCredentials, !old.sharesCredentials {
                try credentials?.startSharing(keys: credentialKeys)
                delegate?.syncedCredentialsChanged()
                try await uploadMissingUsage()
            }

            status = .upToDate(now())
        } catch {
            fail(error)
        }
    }

    /// Fetches what the other Macs changed and applies it; concurrent calls share one fetch.
    func pull() async {
        guard mode != .off, transport != nil else {
            return
        }

        if let pullTask {
            await pullTask.value
            return
        }

        let task = Task { await performPull() }
        pullTask = task
        await task.value
        pullTask = nil
    }

    private func performPull() async {
        guard let transport else {
            return
        }

        do {
            try await flushPendingSettings()
            let changes = try await transport.changes()
            apply(changes, joining: false)
            status = .upToDate(now())
        } catch {
            fail(error)
        }
    }

    /// Checks the account and prepares iCloud; false, with the status saying why, when it can't.
    private func connect() async -> Bool {
        guard let transport else {
            status = .unavailable(unavailableReason(.settingsOnly) ?? "")
            return false
        }

        status = .syncing
        switch await transport.accountStatus() {
        case .available:
            break
        case .noAccount:
            status = .unavailable("Sign in to iCloud in System Settings to sync.")
            return false
        case .restricted:
            status = .unavailable("iCloud is restricted on this Mac.")
            return false
        case .temporarilyUnavailable, .couldNotDetermine:
            status = .failed("iCloud isn't available right now.")
            return false
        }

        do {
            try await transport.prepare()
            return true
        } catch {
            fail(error)
            return false
        }
    }

    private func fail(_ error: any Error) {
        if let error = error as? SyncTransportError, error == .unavailable {
            status = .failed("Can't reach iCloud right now.")
        } else {
            status = .failed("Syncing failed. It will try again.")
        }
        Log.sync.error("failed: \(String(describing: error), privacy: .public)")
    }

    // MARK: Settings

    /// Sends a setting changed on this Mac to the others. A change arriving
    /// from another Mac is not sent back.
    func publish(_ setting: SyncedSetting) {
        guard mode.sharesSettings, transport != nil, !applyingRemote else {
            return
        }

        pendingSettings[setting.recordName] = setting
        Task {
            do {
                try await flushPendingSettings()
            } catch {
                fail(error)
            }
        }
    }

    private func flushPendingSettings() async throws {
        for (name, setting) in pendingSettings {
            try await upload(setting)
            if pendingSettings[name] == setting {
                pendingSettings[name] = nil
            }
        }
    }

    private func upload(_ setting: SyncedSetting) async throws {
        guard let transport else {
            return
        }

        let record = SyncRecord(name: setting.recordName, payload: try encode(setting))
        records[record.name] = try await transport.overwrite(record)
    }

    private func uploadMissingSettings() async throws {
        for setting in delegate?.syncedSettings() ?? [] where records[setting.recordName] == nil {
            try await upload(setting)
        }
    }

    private func encode(_ setting: SyncedSetting) throws -> Data {
        switch setting {
        case let .provider(_, settings): try envelope(settings)
        case let .appearance(appearance): try envelope(appearance)
        case let .alerts(switches): try envelope(switches)
        case let .budget(_, budget): try envelope(budget.map { "\($0)" })
        }
    }

    private func envelope(_ body: some Codable) throws -> Data {
        try SyncCoding.encode(SyncEnvelope(device: deviceID, stamp: now(), body: body))
    }

    // MARK: Applying remote changes

    private func apply(_ changes: SyncChanges, joining: Bool) {
        for name in changes.deleted {
            records[name] = nil
        }

        for record in changes.changed {
            records[record.name] = record
            applyingRemote = true
            applyRemote(record, joining: joining)
            applyingRemote = false
        }
    }

    /// A record from iCloud. This Mac's own writes are skipped, except when
    /// joining: then iCloud's copy wins whoever wrote it.
    private func applyRemote(_ record: SyncRecord, joining: Bool) {
        let parts = record.name.split(separator: ".").map(String.init)
        guard let kind = parts.first else {
            return
        }

        do {
            switch kind {
            case "settings" where mode.sharesSettings:
                if let setting = try decodeSetting(record, parts: parts, joining: joining) {
                    delegate?.applySynced(setting)
                }
            case "usage" where mode.sharesUsage:
                guard parts.count == 3, let provider = Provider(rawValue: parts[1]), let half = Half(rawValue: parts[2]),
                      let state = try body(SharedHalfState.self, record, joining: false)
                else {
                    return
                }
                delegate?.adoptShared(state, for: RefreshTarget(provider: provider, half: half))
            case "history" where mode.sharesUsage:
                // Merging is idempotent, so this Mac's own history may come back.
                guard parts.count == 2, let provider = Provider(rawValue: parts[1]),
                      let history = try body(SharedHistory.self, record, joining: true)
                else {
                    return
                }
                delegate?.mergeHistory(history.samples, for: provider)
            case "org" where mode.sharesUsage:
                guard parts.count == 2, let provider = Provider(rawValue: parts[1]),
                      let organization = try body(SharedOrganization.self, record, joining: joining)
                else {
                    return
                }
                delegate?.adoptOrganization(organization.id, for: provider)
            default:
                // Leases and session claims are only read when needed.
                break
            }
        } catch {
            Log.sync.error("unreadable record \(record.name, privacy: .public): \(String(describing: type(of: error)), privacy: .public)")
        }
    }

    /// The record's body; nil when this Mac wrote it and `joining` is false.
    private func body<Body: Codable>(_ type: Body.Type, _ record: SyncRecord, joining: Bool) throws -> Body? {
        let envelope = try SyncCoding.decode(SyncEnvelope<Body>.self, from: record.payload)
        guard joining || envelope.device != deviceID else {
            return nil
        }

        return envelope.body
    }

    private func decodeSetting(_ record: SyncRecord, parts: [String], joining: Bool) throws -> SyncedSetting? {
        switch (parts.count, parts.count > 1 ? parts[1] : "") {
        case (3, "provider"):
            guard let provider = Provider(rawValue: parts[2]) else {
                return nil
            }
            return try body(ProviderSettings.self, record, joining: joining).map { .provider(provider, $0) }
        case (2, "appearance"):
            return try body(MenuBarAppearance.self, record, joining: joining).map { .appearance($0) }
        case (2, "alerts"):
            return try body(AlertSwitches.self, record, joining: joining).map { .alerts($0) }
        case (3, "budget"):
            guard let provider = Provider(rawValue: parts[2]) else {
                return nil
            }
            let envelope = try SyncCoding.decode(SyncEnvelope<String?>.self, from: record.payload)
            guard joining || envelope.device != deviceID else {
                return nil
            }
            return .budget(provider, envelope.body.flatMap { Decimal(string: $0) })
        default:
            return nil
        }
    }

    // MARK: Fetch turns

    /// Decides whether this Mac asks the provider at a scheduled refresh. It
    /// catches up first; a fresh enough answer from another Mac, or another
    /// Mac fetching now, means no request. iCloud unreachable means fetching
    /// here, as without sync.
    func prepareScheduledFetch(_ target: RefreshTarget, interval: TimeInterval) async -> SyncFetchDecision {
        guard mode.sharesUsage, transport != nil else {
            return .fetch
        }

        await pull()

        if let state = delegate?.sharedState(for: target), state.isShareable, let updated = state.updatedAt,
           now().timeIntervalSince(updated) < interval * Self.freshness {
            Log.sync.debug("\(Self.name(target), privacy: .public): fresh answer shared, no request")
            return .skip
        }

        do {
            return try await claimLease(target) ? .fetch : .skip
        } catch {
            Log.sync.notice("\(Self.name(target), privacy: .public): fetch turn unknown, fetching here")
            return .fetch
        }
    }

    /// Takes the half's fetch turn unless another Mac holds an unexpired one.
    private func claimLease(_ target: RefreshTarget) async throws -> Bool {
        guard let transport else {
            return true
        }

        let name = SyncRecordName.lease(target)
        let current = try await transport.record(named: name)
        if let current, let lease = try? SyncCoding.decode(FetchLease.self, from: current.payload),
           lease.device != deviceID, lease.expiresAt > now() {
            Log.sync.debug("\(Self.name(target), privacy: .public): another Mac is fetching")
            return false
        }

        let lease = FetchLease(device: deviceID, expiresAt: now().addingTimeInterval(Self.leaseDuration))
        do {
            records[name] = try await transport.save(SyncRecord(name: name, payload: try SyncCoding.encode(lease), version: current?.version))
            return true
        } catch let SyncTransportError.conflict(server) {
            records[name] = server
            return false
        }
    }

    /// Gives the other Macs what this Mac's refresh of the half found, and
    /// hands back the fetch turn. `fetched` false (the refresh was skipped)
    /// only hands back the turn. A newer answer already in iCloud wins.
    func publishRefresh(_ target: RefreshTarget, fetched: Bool = true) async {
        guard mode.sharesUsage, transport != nil, let delegate else {
            return
        }

        guard fetched else {
            await releaseLease(target)
            return
        }

        do {
            if let state = delegate.sharedState(for: target), state.isShareable {
                try await saveUsage(state, for: target)
            }
            if target.half == .subscription {
                try await saveHistory(of: target.provider)
            }
        } catch {
            fail(error)
        }

        await releaseLease(target)
    }

    private func saveUsage(_ state: SharedHalfState, for target: RefreshTarget) async throws {
        guard let transport else {
            return
        }

        let name = SyncRecordName.usage(target)
        let payload = try envelope(state)
        var version = records[name]?.version

        for _ in 0..<Self.maxAttempts {
            do {
                records[name] = try await transport.save(SyncRecord(name: name, payload: payload, version: version))
                return
            } catch let SyncTransportError.conflict(server) {
                records[name] = server
                let theirs = try SyncCoding.decode(SyncEnvelope<SharedHalfState>.self, from: server.payload)
                if theirs.body.updatedAt ?? .distantPast >= state.updatedAt ?? .distantPast {
                    if theirs.device != deviceID {
                        applyingRemote = true
                        delegate?.adoptShared(theirs.body, for: target)
                        applyingRemote = false
                    }
                    return
                }
                version = server.version
            }
        }
    }

    /// Saves the union of this Mac's history and iCloud's.
    private func saveHistory(of provider: Provider) async throws {
        guard let transport, let delegate else {
            return
        }

        let name = SyncRecordName.history(provider)
        var version = records[name]?.version

        for _ in 0..<Self.maxAttempts {
            let samples = delegate.historySamples(for: provider)
            guard !samples.isEmpty else {
                return
            }

            do {
                records[name] = try await transport.save(SyncRecord(name: name, payload: try envelope(SharedHistory(samples)), version: version))
                return
            } catch let SyncTransportError.conflict(server) {
                records[name] = server
                let theirs = try SyncCoding.decode(SyncEnvelope<SharedHistory>.self, from: server.payload)
                delegate.mergeHistory(theirs.body.samples, for: provider)
                version = server.version
            }
        }
    }

    /// Ends this Mac's turn early so the next scheduled fetch anywhere may go ahead.
    private func releaseLease(_ target: RefreshTarget) async {
        let name = SyncRecordName.lease(target)
        guard let transport, let mine = records[name],
              let lease = try? SyncCoding.decode(FetchLease.self, from: mine.payload), lease.device == deviceID,
              let payload = try? SyncCoding.encode(FetchLease(device: deviceID, expiresAt: now()))
        else {
            return
        }

        records[name] = try? await transport.save(SyncRecord(name: name, payload: payload, version: mine.version))
    }

    private func uploadMissingUsage() async throws {
        guard let delegate else {
            return
        }

        for provider in Provider.allCases {
            let organization = SyncRecordName.organization(provider)
            if records[organization] == nil, let id = delegate.selectedOrganization(for: provider) {
                try await saveOrganization(id, for: provider)
            }

            for half in [Half.subscription, .api] {
                let target = RefreshTarget(provider: provider, half: half)
                if records[SyncRecordName.usage(target)] == nil, let state = delegate.sharedState(for: target), state.isShareable {
                    try await saveUsage(state, for: target)
                }
            }

            try await saveHistory(of: provider)
        }
    }

    // MARK: Session starts

    /// Claims the provider's automatic session start. False when any Mac
    /// attempted one within `interval`, or another claimed it first. iCloud
    /// unreachable leaves it to this Mac, as without sync.
    func claimSessionStart(_ provider: Provider, within interval: TimeInterval) async -> Bool {
        guard mode.sharesUsage, let transport else {
            return true
        }

        let name = SyncRecordName.session(provider)
        do {
            let current = try await transport.record(named: name)
            if let current, let claim = try? SyncCoding.decode(SessionStartClaim.self, from: current.payload),
               now().timeIntervalSince(claim.attemptedAt) < interval {
                Log.sync.debug("\(provider.rawValue, privacy: .public): a session start was already attempted")
                return false
            }

            let claim = SessionStartClaim(device: deviceID, attemptedAt: now())
            records[name] = try await transport.save(SyncRecord(name: name, payload: try SyncCoding.encode(claim), version: current?.version))
            return true
        } catch SyncTransportError.conflict {
            return false
        } catch {
            Log.sync.notice("\(provider.rawValue, privacy: .public): session start claim unknown, starting here")
            return true
        }
    }

    // MARK: Organizations

    /// Sends the organization chosen on this Mac to the others.
    func publishOrganization(_ id: String?, for provider: Provider) {
        guard mode.sharesUsage, transport != nil, !applyingRemote else {
            return
        }

        Task {
            do {
                try await saveOrganization(id, for: provider)
            } catch {
                fail(error)
            }
        }
    }

    private func saveOrganization(_ id: String?, for provider: Provider) async throws {
        guard let transport else {
            return
        }

        let record = SyncRecord(name: SyncRecordName.organization(provider), payload: try envelope(SharedOrganization(id: id)))
        records[record.name] = try await transport.overwrite(record)
    }

    private static func name(_ target: RefreshTarget) -> String {
        "\(target.provider.rawValue) \(target.half.rawValue)"
    }
}
