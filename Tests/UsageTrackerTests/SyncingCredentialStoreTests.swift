import Foundation
import Testing
@testable import UsageTracker

struct SyncingCredentialStoreTests {
    let local = MemoryCredentialStore()
    let shared = MemoryCredentialStore()
    let token = CredentialKey(provider: .cursor, fieldID: "session-token")
    let admin = CredentialKey(provider: .anthropic, fieldID: "admin-key")

    private var store: SyncingCredentialStore {
        SyncingCredentialStore(local: local, shared: shared)
    }

    @Test func withoutSharingOnlyThisMacsItemsAreUsed() throws {
        let store = store
        shared.values[token] = "icloud"
        try store.set("mine", for: token)

        #expect(try store.credential(for: token) == "mine")
        #expect(shared.values[token] == "icloud")
    }

    @Test func joiningTakesICloudsCopyAndUploadsWhatOnlyThisMacHas() throws {
        let store = store
        local.values[token] = "old"
        shared.values[token] = "icloud"
        local.values[admin] = "adm"

        try store.startSharing(keys: [token, admin])

        #expect(try store.credential(for: token) == "icloud")
        #expect(local.values[token] == "icloud")
        #expect(shared.values[admin] == "adm")
    }

    @Test func whileSharingWritesAndRemovalsReachBoth() throws {
        let store = store
        try store.startSharing(keys: [])

        try store.set("new", for: token)
        #expect(shared.values[token] == "new" && local.values[token] == "new")

        try store.remove(token)
        #expect(shared.values[token] == nil && local.values[token] == nil)
    }

    @Test func aCredentialRemovedOnAnotherMacIsGoneHereToo() throws {
        let store = store
        local.values[token] = "tok"
        try store.startSharing(keys: [token])

        shared.values[token] = nil

        #expect(try store.credential(for: token) == nil)
    }

    @Test func leavingKeepsWhatTheMacsSharedLast() throws {
        let store = store
        try store.startSharing(keys: [])
        shared.values[token] = "rotated elsewhere"
        local.values[admin] = "removed elsewhere"

        try store.stopSharing(keys: [token, admin])

        #expect(try store.credential(for: token) == "rotated elsewhere")
        #expect(local.values[admin] == nil)
    }
}
