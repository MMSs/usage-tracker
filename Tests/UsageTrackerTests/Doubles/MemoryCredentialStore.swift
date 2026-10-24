@testable import UsageTracker

final class MemoryCredentialStore: CredentialStoring {
    var values: [CredentialKey: String] = [:]
    /// When set, `credential(for:)` throws it instead of reading.
    var readError: Error?
    private(set) var removedKeys: [CredentialKey] = []

    func credential(for key: CredentialKey) throws -> String? {
        if let readError {
            throw readError
        }
        return values[key]
    }

    func hasCredential(for key: CredentialKey) throws -> Bool {
        if let readError {
            throw readError
        }
        return values[key] != nil
    }

    func set(_ value: String, for key: CredentialKey) throws {
        values[key] = value
    }

    func remove(_ key: CredentialKey) throws {
        removedKeys.append(key)
        values[key] = nil
    }
}
