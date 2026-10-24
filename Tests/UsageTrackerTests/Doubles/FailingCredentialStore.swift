@testable import UsageTracker

/// A `MemoryCredentialStore` that fails the operations it is told to.
final class FailingCredentialStore: CredentialStoring {
    struct Failure: Error {}

    let base = MemoryCredentialStore()
    var failsReads = false
    var failsWrites = false
    var failsRemovals = false
    /// When set, only `credential(for:)` throws it, as when a Keychain prompt is denied.
    var secretReadError: Error?
    private(set) var secretReads = 0

    func credential(for key: CredentialKey) throws -> String? {
        secretReads += 1
        if let secretReadError {
            throw secretReadError
        }
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
