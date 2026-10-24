import Foundation

protocol APIBudgetStoring: AnyObject {
    func budget(for provider: Provider) -> Decimal?
    func setBudget(_ budget: Decimal?, for provider: Provider)
}

final class UserDefaultsAPIBudgetStore: APIBudgetStoring {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func budget(for provider: Provider) -> Decimal? {
        defaults.string(forKey: key(for: provider)).flatMap { Decimal(string: $0) }
    }

    func setBudget(_ budget: Decimal?, for provider: Provider) {
        guard let budget, budget > 0 else {
            defaults.removeObject(forKey: key(for: provider))
            return
        }

        defaults.set("\(budget)", forKey: key(for: provider))
    }

    private func key(for provider: Provider) -> String {
        "apiBudget.\(provider.rawValue)"
    }
}
