import Foundation
import os

/// Moves the data written under the old bundle identifier to the new one,
/// once, at launch and before any store reads.
///
/// Keychain items move one by one: written under the new service, then
/// deleted from the old one. A failure leaves the old item where it was and
/// the migration retries on the next launch. Settings and cached reports are
/// copied from the old defaults domain, which is then removed. Only counts and
/// status codes are logged, never values.
struct IdentifierMigration {
    static let completedKey = "identifierMigration.completed"

    /// Every Keychain-backed field of every provider.
    static let credentialKeys: [CredentialKey] = ProviderRegistry.all.flatMap { descriptor in
        descriptor.fields.filter { $0.id != CredentialFieldView.budgetFieldID }.map {
            CredentialKey(provider: descriptor.id, fieldID: $0.id)
        }
    }

    let oldCredentials: CredentialStoring
    let newCredentials: CredentialStoring
    /// A `UserDefaults` that can read `oldDomain`.
    let oldDefaults: UserDefaults
    let oldDomain: String
    let newDefaults: UserDefaults

    /// The migration between the two real identifiers.
    static func live() -> IdentifierMigration {
        IdentifierMigration(
            oldCredentials: KeychainCredentialStore(service: AppIdentity.previousBundleID),
            newCredentials: KeychainCredentialStore(service: AppIdentity.bundleID),
            oldDefaults: UserDefaults(suiteName: AppIdentity.previousBundleID) ?? .standard,
            oldDomain: AppIdentity.previousBundleID,
            newDefaults: .standard
        )
    }

    func run() {
        guard !newDefaults.bool(forKey: Self.completedKey) else {
            return
        }

        let keychainComplete = migrateCredentials()
        migrateDefaults()

        // A Keychain failure may be temporary (a locked keychain), so try again next launch.
        if keychainComplete {
            newDefaults.set(true, forKey: Self.completedKey)
        }
    }

    /// Whether every old item was handled without an error.
    private func migrateCredentials() -> Bool {
        var moved = 0
        var kept = 0
        var failed = 0

        for key in Self.credentialKeys {
            do {
                guard let value = try oldCredentials.credential(for: key) else {
                    continue
                }

                if try newCredentials.hasCredential(for: key) {
                    // Already set up under the new identifier; that one wins.
                    kept += 1
                    continue
                }

                try newCredentials.set(value, for: key)
                try oldCredentials.remove(key)
                moved += 1
            } catch {
                failed += 1
                Log.migration.error("\(key.account, privacy: .public): keychain migration failed (\(Self.describe(error), privacy: .public))")
            }
        }

        Log.migration.info("keychain: \(moved) moved, \(kept) already present, \(failed) failed")
        return failed == 0
    }

    private func migrateDefaults() {
        guard let old = oldDefaults.persistentDomain(forName: oldDomain), !old.isEmpty else {
            return
        }

        var copied = 0
        for (key, value) in old where !Self.isSystemKey(key) && newDefaults.object(forKey: key) == nil {
            newDefaults.set(value, forKey: key)
            copied += 1
        }

        oldDefaults.removePersistentDomain(forName: oldDomain)
        Log.migration.info("defaults: \(copied) of \(old.count) keys copied, old domain removed")
    }

    /// AppKit and the system keep their own state per app (status item
    /// positions, window frames); it is not ours to carry over.
    private static func isSystemKey(_ key: String) -> Bool {
        key.hasPrefix("NS") || key.hasPrefix("Apple") || key.hasPrefix("com.apple.")
    }

    /// The OSStatus for a Keychain failure, else the error's type. Never the message.
    private static func describe(_ error: any Error) -> String {
        if case let KeychainCredentialStoreError.unexpectedStatus(status) = error {
            return "status \(status)"
        }

        return String(describing: type(of: error))
    }
}
