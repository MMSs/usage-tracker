import CloudKit
import Foundation

/// The transport in the user's private CloudKit database: one zone, one
/// record type whose `payload` holds a record's JSON. A record's version is
/// its encoded system fields, which carry CloudKit's change tag.
@MainActor
final class CloudKitSyncTransport: SyncTransport {
    static let zoneName = "UsageTracker"
    static let recordType = "Item"
    static let payloadKey = "payload"
    static let subscriptionID = "usage-tracker-changes"
    static let changeTokenKey = "sync.changeToken"

    private let container: CKContainer
    private let defaults: UserDefaults
    private let zoneID = CKRecordZone.ID(zoneName: CloudKitSyncTransport.zoneName, ownerName: CKCurrentUserDefaultName)

    private var database: CKDatabase { container.privateCloudDatabase }

    /// Only call with `SyncEntitlements.hasCloudKit` true: CloudKit traps otherwise.
    init(containerIdentifier: String, defaults: UserDefaults = .standard) {
        container = CKContainer(identifier: containerIdentifier)
        self.defaults = defaults
    }

    func accountStatus() async -> SyncAccountStatus {
        do {
            switch try await container.accountStatus() {
            case .available: return .available
            case .noAccount: return .noAccount
            case .restricted: return .restricted
            case .temporarilyUnavailable: return .temporarilyUnavailable
            default: return .couldNotDetermine
            }
        } catch {
            return .couldNotDetermine
        }
    }

    func prepare() async throws {
        let subscription = CKDatabaseSubscription(subscriptionID: Self.subscriptionID)
        let info = CKSubscription.NotificationInfo()
        // Silent: the app pulls the changes, the user sees nothing.
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info

        do {
            _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
            _ = try await database.modifySubscriptions(saving: [subscription], deleting: [])
        } catch {
            throw Self.map(error)
        }
    }

    func changes() async throws -> SyncChanges {
        var result = SyncChanges()
        var token = storedToken
        var restarts = 0

        while true {
            let page: (
                modificationResultsByID: [CKRecord.ID: Result<CKDatabase.RecordZoneChange.Modification, any Error>],
                deletions: [CKDatabase.RecordZoneChange.Deletion],
                changeToken: CKServerChangeToken,
                moreComing: Bool
            )
            do {
                page = try await database.recordZoneChanges(inZoneWith: zoneID, since: token)
            } catch let error as CKError where restarts < 2 && [.changeTokenExpired, .zoneNotFound].contains(error.code) {
                // An expired token starts over from everything; a missing zone (iCloud data deleted) is made again.
                restarts += 1
                if error.code == .zoneNotFound {
                    try await prepare()
                }
                token = nil
                result = SyncChanges()
                continue
            } catch {
                throw Self.map(error)
            }

            for case let .success(modification) in page.modificationResultsByID.values {
                if let record = syncRecord(modification.record) {
                    result.changed.append(record)
                }
            }
            result.deleted += page.deletions.map(\.recordID.recordName)
            token = page.changeToken

            guard page.moreComing else {
                break
            }
        }

        storedToken = token
        return result
    }

    func resetChanges() {
        storedToken = nil
    }

    func record(named name: String) async throws -> SyncRecord? {
        do {
            return syncRecord(try await database.record(for: recordID(name)))
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        } catch {
            throw Self.map(error)
        }
    }

    func save(_ record: SyncRecord) async throws -> SyncRecord {
        try await save(record, policy: .ifServerRecordUnchanged)
    }

    func overwrite(_ record: SyncRecord) async throws -> SyncRecord {
        try await save(SyncRecord(name: record.name, payload: record.payload), policy: .allKeys)
    }

    private func save(_ record: SyncRecord, policy: CKModifyRecordsOperation.RecordSavePolicy) async throws -> SyncRecord {
        let ckRecord = makeRecord(record)
        ckRecord[Self.payloadKey] = record.payload
        let id = ckRecord.recordID

        let result: Result<CKRecord, any Error>?
        do {
            result = try await database.modifyRecords(saving: [ckRecord], deleting: [], savePolicy: policy, atomically: true).saveResults[id]
        } catch let error as CKError where error.code == .partialFailure {
            result = error.partialErrorsByItemID?[id].map { .failure($0) }
        } catch {
            throw Self.map(error)
        }

        switch result {
        case let .success(saved):
            guard let synced = syncRecord(saved) else {
                throw SyncTransportError.failed
            }
            return synced
        case let .failure(error):
            if let error = error as? CKError, error.code == .serverRecordChanged,
               let server = error.serverRecord.flatMap(syncRecord) {
                throw SyncTransportError.conflict(server)
            }
            throw Self.map(error)
        case nil:
            throw SyncTransportError.failed
        }
    }

    private func recordID(_ name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: zoneID)
    }

    /// The server's record from its encoded system fields, so CloudKit can
    /// compare change tags; a new record without them.
    private func makeRecord(_ record: SyncRecord) -> CKRecord {
        if let version = record.version, let coder = try? NSKeyedUnarchiver(forReadingFrom: version) {
            coder.requiresSecureCoding = true
            defer { coder.finishDecoding() }
            if let existing = CKRecord(coder: coder) {
                return existing
            }
        }

        return CKRecord(recordType: Self.recordType, recordID: recordID(record.name))
    }

    private func syncRecord(_ record: CKRecord) -> SyncRecord? {
        guard let payload = record[Self.payloadKey] as? Data else {
            return nil
        }

        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()

        return SyncRecord(name: record.recordID.recordName, payload: payload, version: coder.encodedData)
    }

    private var storedToken: CKServerChangeToken? {
        get {
            defaults.data(forKey: Self.changeTokenKey).flatMap {
                try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0)
            }
        }
        set {
            let data = newValue.flatMap { try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true) }
            defaults.set(data, forKey: Self.changeTokenKey)
        }
    }

    /// Network, account and throttling errors are worth retrying later; the rest are not.
    private static func map(_ error: any Error) -> SyncTransportError {
        guard let error = error as? CKError else {
            return .failed
        }

        switch error.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy,
             .notAuthenticated, .accountTemporarilyUnavailable:
            return .unavailable
        default:
            return .failed
        }
    }
}
