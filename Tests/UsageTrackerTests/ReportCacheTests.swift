import Foundation
import Testing
@testable import UsageTracker

@Suite struct ReportCacheTests {
    private func makeCachedReport() -> CachedReport {
        let report = ProviderReport(
            planName: "Pro",
            windows: [
                LimitWindow(
                    id: "cycle",
                    label: "Cycle",
                    percentUsed: 42.5,
                    resetsAt: Date(timeIntervalSince1970: 1_800_000_000),
                    parentID: nil
                ),
            ],
            extras: [],
            spend: SpendPeriod(
                period: CyclePeriod(
                    start: Date(timeIntervalSince1970: 1_797_600_000),
                    end: Date(timeIntervalSince1970: 1_800_000_000)
                ),
                spent: 7.5,
                limit: 100,
                unit: .dollars,
                daily: [DaySpend(day: Date(timeIntervalSince1970: 1_797_600_000), amount: 3)]
            )
        )

        return CachedReport(
            report: report,
            fetchedAt: Date(timeIntervalSince1970: 1_799_000_000)
        )
    }

    @Test func aStoredReportRoundTrips() throws {
        let cache = UserDefaultsReportCache(defaults: try makeIsolatedDefaults())
        let cached = makeCachedReport()

        cache.store(cached, provider: .cursor, half: .subscription)

        #expect(cache.cached(provider: .cursor, half: .subscription) == cached)
    }

    @Test func anAbsentReportReadsAsNil() throws {
        let cache = UserDefaultsReportCache(defaults: try makeIsolatedDefaults())

        #expect(cache.cached(provider: .anthropic, half: .api) == nil)
    }

    @Test func corruptDataReadsAsNilWithoutThrowing() throws {
        let defaults = try makeIsolatedDefaults()
        defaults.set(Data("not json".utf8), forKey: "report.cursor.subscription")
        let cache = UserDefaultsReportCache(defaults: defaults)

        #expect(cache.cached(provider: .cursor, half: .subscription) == nil)
    }

    @Test func clearRemovesOnlyTheRequestedHalf() throws {
        let cache = UserDefaultsReportCache(defaults: try makeIsolatedDefaults())
        let cached = makeCachedReport()
        cache.store(cached, provider: .anthropic, half: .subscription)
        cache.store(cached, provider: .anthropic, half: .api)

        cache.clear(provider: .anthropic, half: .subscription)

        #expect(cache.cached(provider: .anthropic, half: .subscription) == nil)
        #expect(cache.cached(provider: .anthropic, half: .api) == cached)
    }

    private func makeIsolatedDefaults() throws -> UserDefaults {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        return defaults
    }
}
