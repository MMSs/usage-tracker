import Foundation

/// The credentials behind this Mac's sync choices, key by key. For a shared
/// key, the iCloud Keychain copy every Mac sees is the one read, and each
/// write or removal goes to it and to this Mac's own item, so leaving keeps
/// a local copy. For every other key only this Mac's items are used.
final class SyncingCredentialStore: CredentialStoring {
    let local: CredentialStoring
    let shared: CredentialStoring
    private(set) var sharedKeys: Set<CredentialKey> = []

    init(local: CredentialStoring, shared: CredentialStoring) {
        self.local = local
        self.shared = shared
    }

    func credential(for key: CredentialKey) throws -> String? {
        try store(for: key).credential(for: key)
    }

    func hasCredential(for key: CredentialKey) throws -> Bool {
        try store(for: key).hasCredential(for: key)
    }

    func set(_ value: String, for key: CredentialKey) throws {
        if sharedKeys.contains(key) {
            try shared.set(value, for: key)
        }
        try local.set(value, for: key)
    }

    func remove(_ key: CredentialKey) throws {
        if sharedKeys.contains(key) {
            try shared.remove(key)
        }
        try local.remove(key)
    }

    /// Starts sharing the keys. A credential already in iCloud replaces this
    /// Mac's; one only this Mac has is uploaded for the others.
    func startSharing(keys: [CredentialKey]) throws {
        for key in keys {
            if let value = try shared.credential(for: key) {
                try local.set(value, for: key)
            } else if let value = try local.credential(for: key) {
                try shared.set(value, for: key)
            }
        }
        sharedKeys.formUnion(keys)
    }

    /// Stops sharing the keys, leaving this Mac with what the Macs shared last.
    func stopSharing(keys: [CredentialKey]) throws {
        let leaving = keys.filter(sharedKeys.contains)
        sharedKeys.subtract(leaving)
        for key in leaving {
            if let value = try shared.credential(for: key) {
                try local.set(value, for: key)
            } else {
                try local.remove(key)
            }
        }
    }

    /// Resumes sharing the keys at launch without copying: both sides were in step when this Mac last ran.
    func resumeSharing(keys: [CredentialKey]) {
        sharedKeys.formUnion(keys)
    }

    private func store(for key: CredentialKey) -> CredentialStoring {
        sharedKeys.contains(key) ? shared : local
    }
}
