import Foundation
import Testing
@testable import UsageTracker

@Suite struct RefreshIntervalStoreTests {
    @Test func anEmptyStoreReadsBackTheDefault() throws {
        let defaults = try makeIsolatedDefaults()

        #expect(UserDefaultsRefreshIntervalStore(defaults: defaults).interval() == .fiveMinutes)
    }

    @Test func aStoredChoiceSurvivesTheRoundTrip() throws {
        let defaults = try makeIsolatedDefaults()

        UserDefaultsRefreshIntervalStore(defaults: defaults).setInterval(.oneHour)

        #expect(UserDefaultsRefreshIntervalStore(defaults: defaults).interval() == .oneHour)
    }

    @Test func anUnrecognizedStoredValueFallsBackToTheDefault() throws {
        let defaults = try makeIsolatedDefaults()
        defaults.set("thirtySeconds", forKey: "refreshInterval")

        #expect(UserDefaultsRefreshIntervalStore(defaults: defaults).interval() == .fiveMinutes)
    }

    private func makeIsolatedDefaults() throws -> UserDefaults {
        let suiteName = "com.mohab.usage-tracker.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        return defaults
    }
}
