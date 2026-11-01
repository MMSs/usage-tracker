import Foundation
import Testing
@testable import UsageTracker

struct SyncPreferencesStoreTests {
    private func store(_ prepare: (UserDefaults) -> Void = { _ in }) -> UserDefaultsSyncPreferencesStore {
        let defaults = UserDefaults(suiteName: "SyncPreferencesStoreTests.\(UUID().uuidString)")!
        prepare(defaults)
        return UserDefaultsSyncPreferencesStore(defaults: defaults)
    }

    @Test func nothingIsSharedUntilChosen() {
        #expect(store().choices == .nothing)
    }

    @Test func choicesRoundTrip() {
        let store = store()
        let choices = SyncChoices(sharesSettings: false, sharedProviders: [.cursor, .openai])

        store.choices = choices

        #expect(store.choices == choices)
    }

    @Test func theOldSingleChoiceCarriesOver() {
        let everything = store { $0.set("everything", forKey: "sync.mode") }
        let settingsOnly = store { $0.set("settingsOnly", forKey: "sync.mode") }
        let off = store { $0.set("off", forKey: "sync.mode") }

        #expect(everything.choices == .everything)
        #expect(settingsOnly.choices == SyncChoices(sharesSettings: true))
        #expect(off.choices == .nothing)
    }

    @Test func aNewChoiceReplacesTheOldOne() {
        let store = store { $0.set("everything", forKey: "sync.mode") }

        store.choices = .nothing

        #expect(store.choices == .nothing)
    }
}
