import Foundation
import Testing
@testable import UsageTracker

@Suite struct SessionModelStoreTests {
    @Test func defaultsAreTheCheapestKnownModels() {
        withIsolatedDefaults { defaults in
            let store = UserDefaultsSessionModelStore(defaults: defaults)
            #expect(store.model(for: .anthropic) == "claude-haiku-5-5")
            #expect(store.model(for: .openai) == "gpt-6-luna")
            #expect(UserDefaultsSessionModelStore.defaultModels == [.anthropic: "claude-haiku-5-5", .openai: "gpt-6-luna"])
        }
    }

    @Test func aStoredModelOverridesTheDefault() {
        withIsolatedDefaults { defaults in
            defaults.set("custom-model", forKey: "sessionStart.model.anthropic")
            let store = UserDefaultsSessionModelStore(defaults: defaults)
            #expect(store.model(for: .anthropic) == "custom-model")
            #expect(store.model(for: .openai) == "gpt-6-luna")
        }
    }

    @Test func aBlankStoredModelFallsBackToTheDefault() {
        withIsolatedDefaults { defaults in
            defaults.set("  \n", forKey: "sessionStart.model.openai")
            let store = UserDefaultsSessionModelStore(defaults: defaults)
            #expect(store.model(for: .openai) == "gpt-6-luna")
        }
    }
}
