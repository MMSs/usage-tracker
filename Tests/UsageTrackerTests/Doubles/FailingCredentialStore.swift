@testable import UsageTracker

/// A `MemoryCredentialStore` that fails the operations it is told to.
final class FailingCredentialStore: CredentialStoring {
    struct Failure: Error {}

    let base = MemoryCredentialStore()
    var failsReads = false
    var failsWrites = false
    var failsRemovals = false

    func credential(for key: CredentialKey) throws -> String? {
        if failsReads {
            throw Failure()
        }
        return try base.credential(for: key)
    }

    func hasCredential(for key: CredentialKey) throws -> Bool {
        if failsReads {
            throw Failure()
        }
        return try base.hasCredential(for: key)
    }

    func set(_ value: String, for key: CredentialKey) throws {
        if failsWrites {
            throw Failure()
        }
        try base.set(value, for: key)
    }

    func remove(_ key: CredentialKey) throws {
        if failsRemovals {
            throw Failure()
        }
        try base.remove(key)
    }
}
