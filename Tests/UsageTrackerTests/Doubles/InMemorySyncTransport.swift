import Foundation
@testable import UsageTracker

/// The user's iCloud, shared by every `InMemorySyncTransport` made on it, so
/// a test can run several Macs against one account.
@MainActor
final class InMemorySyncServer {
    struct Entry {
        var payload: Data
        var version: Int
        var sequence: Int
    }

    private(set) var entries: [String: Entry] = [:]
    private(set) var sequence = 0
    private(set) var saveCount = 0
    /// False: every call throws `.unavailable`, as offline.
    var isReachable = true
    var account: SyncAccountStatus = .available

    func payload(_ name: String) -> Data? {
        entries[name]?.payload
    }

    func put(_ name: String, payload: Data) -> SyncRecord {
        sequence += 1
        saveCount += 1
        let version = (entries[name]?.version ?? 0) + 1
        entries[name] = Entry(payload: payload, version: version, sequence: sequence)
        return record(name)!
    }

    func record(_ name: String) -> SyncRecord? {
        entries[name].map { SyncRecord(name: name, payload: $0.payload, version: Data("\($0.version)".utf8)) }
    }
}

@MainActor
final class InMemorySyncTransport: SyncTransport {
    let server: InMemorySyncServer
    private var seen = 0
    private(set) var prepareCount = 0

    init(server: InMemorySyncServer) {
        self.server = server
    }

    func accountStatus() async -> SyncAccountStatus {
        server.account
    }

    func prepare() async throws {
        try check()
        prepareCount += 1
    }

    func changes() async throws -> SyncChanges {
        try check()
        let changed = server.entries
            .filter { $0.value.sequence > seen }
            .sorted { $0.value.sequence < $1.value.sequence }
            .compactMap { server.record($0.key) }
        seen = server.sequence
        return SyncChanges(changed: changed)
    }

    func resetChanges() {
        seen = 0
    }

    func record(named name: String) async throws -> SyncRecord? {
        try check()
        return server.record(name)
    }

    func save(_ record: SyncRecord) async throws -> SyncRecord {
        try check()
        if let current = server.record(record.name), current.version != record.version {
            throw SyncTransportError.conflict(current)
        }
        if server.record(record.name) == nil, record.version != nil {
            throw SyncTransportError.failed
        }
        return server.put(record.name, payload: record.payload)
    }

    func overwrite(_ record: SyncRecord) async throws -> SyncRecord {
        try check()
        return server.put(record.name, payload: record.payload)
    }

    private func check() throws {
        guard server.isReachable else {
            throw SyncTransportError.unavailable
        }
    }
}
