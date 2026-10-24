import Foundation
import os
import Security

/// Moves the data written under the old bundle identifier to the new one,
/// once, at launch and before any store reads.
///
/// Keychain items move one by one: written under the new service, then
/// deleted from the old one. The old secret is only read when a move is
/// needed, since each read may raise a Keychain prompt. A failure leaves the
/// old item where it was; temporary failures retry for a few launches, denied
/// access or an unreadable value does not. Settings and cached reports are
/// copied from the old defaults domain, which is then removed. Only counts and
/// status codes are logged, never values.
struct IdentifierMigration {
    static let completedKey = "identifierMigration.completed"
    static let attemptsKey = "identifierMigration.attempts"
    /// Launches that may retry a temporary Keychain failure before giving up.
    static let maxAttempts = 3

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

        let outcome = migrateCredentials()
        migrateDefaults()

        guard outcome.retryable > 0 else {
            newDefaults.set(true, forKey: Self.completedKey)
            return
        }

        // A temporary failure (a locked keychain) is worth another launch, but
        // not forever: each retry may raise a Keychain prompt.
        let attempts = newDefaults.integer(forKey: Self.attemptsKey) + 1
        newDefaults.set(attempts, forKey: Self.attemptsKey)
        if attempts >= Self.maxAttempts {
            newDefaults.set(true, forKey: Self.completedKey)
            Log.migration.error("keychain: giving up after \(attempts) launches, \(outcome.retryable) item(s) left in the old service")
        }
    }

    private struct CredentialOutcome {
        var moved = 0
        var kept = 0
        /// Failed in a way another launch may fix.
        var retryable = 0
        /// Failed in a way another launch will not fix (denied access, undecodable value).
        var terminal = 0
    }

    private func migrateCredentials() -> CredentialOutcome {
        var outcome = CredentialOutcome()

        for key in Self.credentialKeys {
            do {
                // Cheap checks first: they never read a secret, so they never prompt.
                if try newCredentials.hasCredential(for: key) {
                    // Already set up under the new identifier; that one wins.
                    outcome.kept += 1
                    continue
                }

                guard try oldCredentials.hasCredential(for: key) else {
                    continue
                }

                guard let value = try oldCredentials.credential(for: key) else {
                    continue
                }

                try newCredentials.set(value, for: key)
                try oldCredentials.remove(key)
                outcome.moved += 1
            } catch {
                if Self.isTerminal(error) {
                    outcome.terminal += 1
                } else {
                    outcome.retryable += 1
                }
                Log.migration.error("\(key.account, privacy: .public): keychain migration failed (\(Self.describe(error), privacy: .public))")
            }
        }

        Log.migration.info("keychain: \(outcome.moved) moved, \(outcome.kept) already present, \(outcome.retryable) failed, \(outcome.terminal) given up")
        return outcome
    }

    /// The owner said no, or the value can never be read; asking again changes nothing.
    private static func isTerminal(_ error: any Error) -> Bool {
        switch error as? KeychainCredentialStoreError {
        case .invalidValue:
            true
        case let .unexpectedStatus(status):
            status == errSecAuthFailed || status == errSecUserCanceled
        case nil:
            false
        }
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
