import Testing
@testable import UsageTracker

@Suite struct CredentialKeyTests {
    @Test func accountNameIsProviderDashField() {
        #expect(CredentialKey(provider: .cursor, fieldID: "session-token").account == "cursor-session-token")
    }

    @Test func memoryStoreRoundTripsAndRemoves() throws {
        let store = MemoryCredentialStore()
        let key = CredentialKey(provider: .openai, fieldID: "admin-key")
        try store.set("x", for: key)
        #expect(try store.credential(for: key) == "x")
        try store.remove(key)
        #expect(try store.credential(for: key) == nil)
    }
}
