import Foundation

/// The credentials for this Mac's sync mode. With credentials shared, the
/// iCloud Keychain copy every Mac sees is the one read, and each write or
/// removal goes to it and to this Mac's own item, so leaving keeps a local
/// copy. Otherwise only this Mac's items are used.
final class SyncingCredentialStore: CredentialStoring {
    let local: CredentialStoring
    let shared: CredentialStoring
    private(set) var sharesCredentials = false

    init(local: CredentialStoring, shared: CredentialStoring) {
        self.local = local
        self.shared = shared
    }

    func credential(for key: CredentialKey) throws -> String? {
        try (sharesCredentials ? shared : local).credential(for: key)
    }

    func hasCredential(for key: CredentialKey) throws -> Bool {
        try (sharesCredentials ? shared : local).hasCredential(for: key)
    }

    func set(_ value: String, for key: CredentialKey) throws {
        if sharesCredentials {
            try shared.set(value, for: key)
        }
        try local.set(value, for: key)
    }

    func remove(_ key: CredentialKey) throws {
        if sharesCredentials {
            try shared.remove(key)
        }
        try local.remove(key)
    }

    /// Starts sharing. A credential already in iCloud replaces this Mac's;
    /// one only this Mac has is uploaded for the others.
    func startSharing(keys: [CredentialKey]) throws {
        for key in keys {
            if let value = try shared.credential(for: key) {
                try local.set(value, for: key)
            } else if let value = try local.credential(for: key) {
                try shared.set(value, for: key)
            }
        }
        sharesCredentials = true
    }

    /// Stops sharing, leaving this Mac with what the Macs shared last.
    func stopSharing(keys: [CredentialKey]) throws {
        guard sharesCredentials else {
            return
        }

        sharesCredentials = false
        for key in keys {
            if let value = try shared.credential(for: key) {
                try local.set(value, for: key)
            } else {
                try local.remove(key)
            }
        }
    }

    /// Resumes sharing at launch without copying: both sides were in step when this Mac last ran.
    func resumeSharing() {
        sharesCredentials = true
    }
}
