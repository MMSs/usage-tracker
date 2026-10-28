import Foundation

/// One item in the user's private iCloud: a name, a JSON payload, and the
/// server's version of it.
struct SyncRecord: Equatable, Sendable {
    let name: String
    var payload: Data
    /// The version the server last returned; nil for an item never saved.
    /// A compare-and-swap save sends it back.
    var version: Data?

    init(name: String, payload: Data, version: Data? = nil) {
        self.name = name
        self.payload = payload
        self.version = version
    }
}

/// What changed in iCloud since the transport last asked.
struct SyncChanges: Equatable, Sendable {
    var changed: [SyncRecord] = []
    var deleted: [String] = []
}

enum SyncAccountStatus: Equatable, Sendable {
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine
}

enum SyncTransportError: Error, Equatable {
    /// The server holds another version; the save can be retried on top of it.
    case conflict(SyncRecord)
    /// No connection, no account, or iCloud is busy: try again later.
    case unavailable
    /// Anything else; the type name only is logged.
    case failed
}

/// The user's private iCloud as Usage Tracker uses it: a flat set of named
/// records, read as changes since the last read, saved with or without
/// compare-and-swap.
@MainActor
protocol SyncTransport: AnyObject {
    func accountStatus() async -> SyncAccountStatus
    /// Creates the storage and the change subscription; safe to repeat.
    func prepare() async throws
    /// Records changed or deleted since the last call; everything the first
    /// time and after `resetChanges()`.
    func changes() async throws -> SyncChanges
    func resetChanges()
    func record(named name: String) async throws -> SyncRecord?
    /// Saves only while the server still holds `record.version` (none, when
    /// nil); otherwise throws `.conflict` with the server's record.
    func save(_ record: SyncRecord) async throws -> SyncRecord
    /// Saves over whatever the server holds.
    func overwrite(_ record: SyncRecord) async throws -> SyncRecord
}
