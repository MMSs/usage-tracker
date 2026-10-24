import Foundation
import Testing
@testable import UsageTracker

@Suite struct APIBudgetStoreTests {
    private func withStore(_ body: (UserDefaultsAPIBudgetStore) -> Void) {
        withIsolatedDefaults { body(UserDefaultsAPIBudgetStore(defaults: $0)) }
    }

    @Test func roundTripsAndClearsWithNil() {
        withStore { store in
            #expect(store.budget(for: .anthropic) == nil)

            store.setBudget(Decimal(string: "123.45"), for: .anthropic)
            #expect(store.budget(for: .anthropic) == Decimal(string: "123.45"))
            #expect(store.budget(for: .openai) == nil)

            store.setBudget(nil, for: .anthropic)
            #expect(store.budget(for: .anthropic) == nil)
        }
    }

    @Test func nonPositiveBudgetIsStoredAsNil() {
        withStore { store in
            store.setBudget(50, for: .openai)

            store.setBudget(0, for: .openai)
            #expect(store.budget(for: .openai) == nil)

            store.setBudget(50, for: .openai)
            store.setBudget(-5, for: .openai)
            #expect(store.budget(for: .openai) == nil)
        }
    }
}
