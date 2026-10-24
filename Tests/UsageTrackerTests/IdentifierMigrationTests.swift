import Foundation
import Security
import Testing
@testable import UsageTracker

@Suite struct IdentifierMigrationTests {
    private let cursorToken = CredentialKey(provider: .cursor, fieldID: "session-token")
    private let anthropicSession = CredentialKey(provider: .anthropic, fieldID: "session-key")
    private let anthropicAdmin = CredentialKey(provider: .anthropic, fieldID: "admin-key")

    /// Runs `body` with an old and a new defaults domain, both isolated.
    private func withDomains(
        _ body: (_ old: UserDefaults, _ oldDomain: String, _ new: UserDefaults) throws -> Void
    ) rethrows {
        let old = IsolatedDefaults()
        let new = IsolatedDefaults()
        defer {
            old.remove()
            new.remove()
        }

        try body(old.defaults, old.suiteName, new.defaults)
    }

    private func migration(
        old: CredentialStoring,
        new: CredentialStoring,
        oldDefaults: UserDefaults,
        oldDomain: String,
        newDefaults: UserDefaults
    ) -> IdentifierMigration {
        IdentifierMigration(
            oldCredentials: old,
            newCredentials: new,
            oldDefaults: oldDefaults,
            oldDomain: oldDomain,
            newDefaults: newDefaults
        )
    }

    @Test func knownKeysAreEveryRegistryFieldExceptTheBudget() {
        let keys = IdentifierMigration.credentialKeys
        #expect(keys.contains(cursorToken))
        #expect(keys.contains(anthropicSession))
        #expect(keys.contains(anthropicAdmin))
        #expect(!keys.contains { $0.fieldID == "api-budget" })
    }

    @Test func movesCredentialsToTheNewStoreAndRemovesTheOldOnes() {
        let old = MemoryCredentialStore()
        let new = MemoryCredentialStore()
        old.values = [cursorToken: "c", anthropicAdmin: "a"]

        withDomains { oldDefaults, oldDomain, newDefaults in
            migration(old: old, new: new, oldDefaults: oldDefaults, oldDomain: oldDomain, newDefaults: newDefaults).run()
        }

        #expect(new.values == [cursorToken: "c", anthropicAdmin: "a"])
        #expect(old.values.isEmpty)
    }

    @Test func keepsAnExistingNewCredentialAndLeavesTheOldOne() {
        let old = MemoryCredentialStore()
        let new = MemoryCredentialStore()
        old.values = [cursorToken: "old", anthropicAdmin: "a"]
        new.values = [cursorToken: "new"]

        withDomains { oldDefaults, oldDomain, newDefaults in
            migration(old: old, new: new, oldDefaults: oldDefaults, oldDomain: oldDomain, newDefaults: newDefaults).run()
        }

        #expect(new.values == [cursorToken: "new", anthropicAdmin: "a"])
        #expect(old.values == [cursorToken: "old"])
    }

    @Test func aFailedWriteLeavesTheOldItemAndTheRestStillMove() {
        let old = MemoryCredentialStore()
        let new = FailingCredentialStore()
        old.values = [cursorToken: "c"]
        new.failsWrites = true

        withDomains { oldDefaults, oldDomain, newDefaults in
            migration(old: old, new: new, oldDefaults: oldDefaults, oldDomain: oldDomain, newDefaults: newDefaults).run()
            #expect(!newDefaults.bool(forKey: IdentifierMigration.completedKey))

            // The next launch retries and succeeds.
            new.failsWrites = false
            migration(old: old, new: new, oldDefaults: oldDefaults, oldDomain: oldDomain, newDefaults: newDefaults).run()
            #expect(newDefaults.bool(forKey: IdentifierMigration.completedKey))
        }

        #expect(new.base.values == [cursorToken: "c"])
        #expect(old.values.isEmpty)
    }

    @Test func aFailedRemovalKeepsTheOldItemAndTheNewCopy() {
        let old = FailingCredentialStore()
        let new = MemoryCredentialStore()
        old.base.values = [cursorToken: "c"]
        old.failsRemovals = true

        withDomains { oldDefaults, oldDomain, newDefaults in
            let migration = migration(old: old, new: new, oldDefaults: oldDefaults, oldDomain: oldDomain, newDefaults: newDefaults)
            migration.run()
            #expect(new.values == [cursorToken: "c"])
            #expect(old.base.values == [cursorToken: "c"])
            #expect(!newDefaults.bool(forKey: IdentifierMigration.completedKey))

            // The copy is already in place, so the next launch has nothing left to do.
            migration.run()
            #expect(newDefaults.bool(forKey: IdentifierMigration.completedKey))
        }
    }

    @Test func anExistingNewItemIsNeverReadFromTheOldStore() {
        let old = FailingCredentialStore()
        let new = MemoryCredentialStore()
        old.base.values = [cursorToken: "old"]
        old.secretReadError = KeychainCredentialStoreError.unexpectedStatus(errSecAuthFailed)
        new.values = [cursorToken: "new"]

        withDomains { oldDefaults, oldDomain, newDefaults in
            migration(old: old, new: new, oldDefaults: oldDefaults, oldDomain: oldDomain, newDefaults: newDefaults).run()
            #expect(newDefaults.bool(forKey: IdentifierMigration.completedKey))
        }

        #expect(old.secretReads == 0)
        #expect(new.values == [cursorToken: "new"])
    }

    @Test func aMissingOldItemIsNeverReadEither() {
        let old = FailingCredentialStore()
        let new = MemoryCredentialStore()

        withDomains { oldDefaults, oldDomain, newDefaults in
            migration(old: old, new: new, oldDefaults: oldDefaults, oldDomain: oldDomain, newDefaults: newDefaults).run()
        }

        #expect(old.secretReads == 0)
    }

    @Test(arguments: [
        KeychainCredentialStoreError.unexpectedStatus(errSecAuthFailed),
        KeychainCredentialStoreError.unexpectedStatus(errSecUserCanceled),
        KeychainCredentialStoreError.invalidValue,
    ])
    func aDeniedOrUnreadableOldItemIsNotRetried(error: KeychainCredentialStoreError) {
        let old = FailingCredentialStore()
        let new = MemoryCredentialStore()
        old.base.values = [cursorToken: "c"]
        old.secretReadError = error

        withDomains { oldDefaults, oldDomain, newDefaults in
            migration(old: old, new: new, oldDefaults: oldDefaults, oldDomain: oldDomain, newDefaults: newDefaults).run()
            #expect(newDefaults.bool(forKey: IdentifierMigration.completedKey))
        }

        #expect(new.values.isEmpty)
        #expect(old.base.values == [cursorToken: "c"])
        #expect(old.secretReads == 1)
    }

    @Test func aTemporaryKeychainFailureRetriesForAFewLaunchesThenGivesUp() {
        let old = FailingCredentialStore()
        let new = MemoryCredentialStore()
        old.base.values = [cursorToken: "c"]
        old.secretReadError = KeychainCredentialStoreError.unexpectedStatus(errSecInteractionNotAllowed)

        withDomains { oldDefaults, oldDomain, newDefaults in
            let migration = migration(old: old, new: new, oldDefaults: oldDefaults, oldDomain: oldDomain, newDefaults: newDefaults)

            for _ in 1..<IdentifierMigration.maxAttempts {
                migration.run()
                #expect(!newDefaults.bool(forKey: IdentifierMigration.completedKey))
            }

            migration.run()
            #expect(newDefaults.bool(forKey: IdentifierMigration.completedKey))

            migration.run()
            #expect(old.secretReads == IdentifierMigration.maxAttempts)
        }

        #expect(new.values.isEmpty)
        #expect(old.base.values == [cursorToken: "c"])
    }

    @Test func anUnreadableOldStoreChangesNothing() {
        let old = FailingCredentialStore()
        let new = MemoryCredentialStore()
        old.base.values = [cursorToken: "c"]
        old.failsReads = true

        withDomains { oldDefaults, oldDomain, newDefaults in
            migration(old: old, new: new, oldDefaults: oldDefaults, oldDomain: oldDomain, newDefaults: newDefaults).run()
            #expect(!newDefaults.bool(forKey: IdentifierMigration.completedKey))
        }

        #expect(new.values.isEmpty)
        #expect(old.base.values == [cursorToken: "c"])
    }

    @Test func copiesSettingsButNotSystemKeysThenRemovesTheOldDomain() {
        withDomains { oldDefaults, oldDomain, newDefaults in
            oldDefaults.set(Data([1, 2]), forKey: "providerSettings.cursor")
            oldDefaults.set(42.5, forKey: "apiBudget.anthropic")
            oldDefaults.set("1", forKey: "NSStatusItem Visible Item-0")
            oldDefaults.set("0 0 10 10", forKey: "NSWindow Frame Settings")
            oldDefaults.set(2, forKey: "AppleExampleSetting")
            oldDefaults.set("x", forKey: "com.apple.example")

            migration(
                old: MemoryCredentialStore(), new: MemoryCredentialStore(),
                oldDefaults: oldDefaults, oldDomain: oldDomain, newDefaults: newDefaults
            ).run()

            #expect(newDefaults.data(forKey: "providerSettings.cursor") == Data([1, 2]))
            #expect(newDefaults.double(forKey: "apiBudget.anthropic") == 42.5)
            #expect(newDefaults.object(forKey: "NSStatusItem Visible Item-0") == nil)
            #expect(newDefaults.object(forKey: "NSWindow Frame Settings") == nil)
            #expect(newDefaults.object(forKey: "AppleExampleSetting") == nil)
            #expect(newDefaults.object(forKey: "com.apple.example") == nil)
            #expect(oldDefaults.persistentDomain(forName: oldDomain)?.isEmpty ?? true)
        }
    }

    @Test func doesNotOverwriteASettingTheNewDomainAlreadyHas() {
        withDomains { oldDefaults, oldDomain, newDefaults in
            oldDefaults.set(1.0, forKey: "apiBudget.anthropic")
            newDefaults.set(9.0, forKey: "apiBudget.anthropic")

            migration(
                old: MemoryCredentialStore(), new: MemoryCredentialStore(),
                oldDefaults: oldDefaults, oldDomain: oldDomain, newDefaults: newDefaults
            ).run()

            #expect(newDefaults.double(forKey: "apiBudget.anthropic") == 9.0)
        }
    }

    @Test func runsOnlyOnce() throws {
        let old = MemoryCredentialStore()
        let new = MemoryCredentialStore()
        old.values = [cursorToken: "c"]

        try withDomains { oldDefaults, oldDomain, newDefaults in
            let migration = migration(old: old, new: new, oldDefaults: oldDefaults, oldDomain: oldDomain, newDefaults: newDefaults)
            migration.run()
            #expect(newDefaults.bool(forKey: IdentifierMigration.completedKey))

            // Data that shows up under the old identifier later is left alone.
            try old.set("late", for: anthropicAdmin)
            oldDefaults.set(1, forKey: "late")
            migration.run()
            #expect(new.values == [cursorToken: "c"])
            #expect(old.values == [anthropicAdmin: "late"])
            #expect(newDefaults.object(forKey: "late") == nil)
        }
    }

    @Test func aFreshInstallChangesNothing() {
        let old = MemoryCredentialStore()
        let new = MemoryCredentialStore()

        withDomains { oldDefaults, oldDomain, newDefaults in
            migration(old: old, new: new, oldDefaults: oldDefaults, oldDomain: oldDomain, newDefaults: newDefaults).run()

            #expect(new.values.isEmpty)
            #expect(old.removedKeys.isEmpty)
            #expect(oldDefaults.persistentDomain(forName: oldDomain)?.isEmpty ?? true)
        }

        #expect(new.removedKeys.isEmpty)
    }
}
