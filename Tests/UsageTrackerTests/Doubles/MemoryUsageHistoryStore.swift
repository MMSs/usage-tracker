import Foundation
@testable import UsageTracker

final class MemoryUsageHistoryStore: UsageHistoryStoring {
    var stored: [String: [UsageSample]] = [:]
    private(set) var recorded: [(ProviderReport, Provider, Date)] = []
    private(set) var clearCount = 0

    func record(_ report: ProviderReport, provider: Provider, at date: Date) {
        recorded.append((report, provider, date))
    }

    func samples(provider: Provider, now: Date) -> [String: [UsageSample]] {
        stored
    }

    func clear(provider: Provider) {
        clearCount += 1
    }
}
