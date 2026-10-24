import Foundation
@testable import UsageTracker

final class MemoryAPIBudgetStore: APIBudgetStoring {
    private var budgets: [Provider: Decimal] = [:]

    func budget(for provider: Provider) -> Decimal? {
        budgets[provider]
    }

    func setBudget(_ budget: Decimal?, for provider: Provider) {
        budgets[provider] = budget
    }
}
