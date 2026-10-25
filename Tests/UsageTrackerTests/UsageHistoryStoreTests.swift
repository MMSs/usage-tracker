import Foundation
import Testing
@testable import UsageTracker

struct UsageHistoryStoreTests {
    /// Minute-aligned (whole seconds divisible by 60): samples share a minute
    /// by offset from here, not by where the clock happens to fall.
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func report(_ windows: [(String, Double)]) -> ProviderReport {
        ProviderReport(
            planName: nil,
            windows: windows.map {
                LimitWindow(id: $0.0, label: $0.0, percentUsed: $0.1, resetsAt: nil, parentID: nil)
            },
            extras: [],
            spend: nil
        )
    }

    private func hours(_ count: Double) -> TimeInterval { count * 3600 }

    @Test func encodingRoundTripsInFiveBytesASample() {
        let samples = [
            UsageSample(date: start, percent: 12),
            UsageSample(date: start.addingTimeInterval(90), percent: 255),
        ]
        let data = UsageSampleCoding.encode(samples)

        #expect(data.count == 10)
        #expect(UsageSampleCoding.decode(data) == samples)
        #expect(UsageSampleCoding.decode(data + Data([1, 2])) == samples)
    }

    @Test func recordAppendsEveryWindow() {
        withIsolatedDefaults { defaults in
            let store = UserDefaultsUsageHistoryStore(defaults: defaults)

            store.record(report([("session", 41.4), ("weekly", 10.6), ("opus", 3)]), provider: .anthropic, at: start)

            #expect(store.samples(provider: .anthropic, now: start) == [
                "session": [UsageSample(date: start, percent: 41)],
                "weekly": [UsageSample(date: start, percent: 11)],
                "opus": [UsageSample(date: start, percent: 3)],
            ])
        }
    }

    @Test func samplesOlderThanADayAreDroppedOnWrite() {
        withIsolatedDefaults { defaults in
            let store = UserDefaultsUsageHistoryStore(defaults: defaults)
            let later = start.addingTimeInterval(hours(23))
            let latest = start.addingTimeInterval(hours(25))

            store.record(report([("session", 10)]), provider: .anthropic, at: start)
            store.record(report([("session", 20)]), provider: .anthropic, at: later)
            store.record(report([("session", 30)]), provider: .anthropic, at: latest)

            #expect(store.samples(provider: .anthropic, now: latest)["session"] == [
                UsageSample(date: later, percent: 20),
                UsageSample(date: latest, percent: 30),
            ])
        }
    }

    @Test func aWindowMissingFromTheReportAgesOut() {
        withIsolatedDefaults { defaults in
            let store = UserDefaultsUsageHistoryStore(defaults: defaults)
            let later = start.addingTimeInterval(hours(25))

            store.record(report([("session", 10), ("opus", 5)]), provider: .anthropic, at: start)
            store.record(report([("session", 20)]), provider: .anthropic, at: later)

            let samples = store.samples(provider: .anthropic, now: later)
            #expect(samples["opus"] == nil)
            #expect(samples["session"] == [UsageSample(date: later, percent: 20)])
        }
    }

    @Test func aSampleWithinAMinuteReplacesTheLastOne() {
        withIsolatedDefaults { defaults in
            let store = UserDefaultsUsageHistoryStore(defaults: defaults)
            let soon = start.addingTimeInterval(30)
            let afterAMinute = start.addingTimeInterval(61)

            store.record(report([("session", 41)]), provider: .anthropic, at: start)
            store.record(report([("session", 42)]), provider: .anthropic, at: soon)

            #expect(store.samples(provider: .anthropic, now: soon)["session"] == [
                UsageSample(date: soon, percent: 42),
            ])

            store.record(report([("session", 43)]), provider: .anthropic, at: afterAMinute)

            #expect(store.samples(provider: .anthropic, now: afterAMinute)["session"] == [
                UsageSample(date: soon, percent: 42),
                UsageSample(date: afterAMinute, percent: 43),
            ])
        }
    }

    @Test func aThirtySecondRefreshKeepsOneSamplePerMinute() {
        withIsolatedDefaults { defaults in
            let store = UserDefaultsUsageHistoryStore(defaults: defaults)

            for index in 0..<20 {
                store.record(report([("session", Double(index))]), provider: .anthropic, at: start.addingTimeInterval(Double(index) * 30))
            }

            let samples = store.samples(provider: .anthropic, now: start.addingTimeInterval(600))["session"]
            let expected = (0..<10).map { minute in
                UsageSample(date: start.addingTimeInterval(Double(minute) * 60 + 30), percent: UInt8(minute * 2 + 1))
            }
            #expect(samples == expected)
        }
    }

    @Test func aClockSetBackDropsSamplesFromTheFuture() {
        withIsolatedDefaults { defaults in
            let store = UserDefaultsUsageHistoryStore(defaults: defaults)
            let earlier = start.addingTimeInterval(-hours(1))

            store.record(report([("session", 10)]), provider: .anthropic, at: start)
            store.record(report([("session", 20)]), provider: .anthropic, at: earlier)

            #expect(store.samples(provider: .anthropic, now: start)["session"] == [
                UsageSample(date: earlier, percent: 20),
            ])
        }
    }

    @Test func percentsClampAndNonFiniteWindowsAreSkipped() {
        withIsolatedDefaults { defaults in
            let store = UserDefaultsUsageHistoryStore(defaults: defaults)

            store.record(
                report([("over", 140), ("huge", 300), ("negative", -5), ("nan", .nan), ("inf", .infinity)]),
                provider: .cursor,
                at: start
            )

            let samples = store.samples(provider: .cursor, now: start)
            #expect(samples["over"]?.first?.percent == 140)
            #expect(samples["huge"]?.first?.percent == 255)
            #expect(samples["negative"]?.first?.percent == 0)
            #expect(samples["nan"] == nil)
            #expect(samples["inf"] == nil)
        }
    }

    @Test func samplesReadsOnlyTheLastDay() {
        withIsolatedDefaults { defaults in
            let store = UserDefaultsUsageHistoryStore(defaults: defaults)
            let recent = start.addingTimeInterval(hours(2))
            let now = start.addingTimeInterval(hours(25))

            store.record(report([("session", 10)]), provider: .anthropic, at: start)
            store.record(report([("session", 20)]), provider: .anthropic, at: recent)

            #expect(store.samples(provider: .anthropic, now: now) == [
                "session": [UsageSample(date: recent, percent: 20)],
            ])
            #expect(store.samples(provider: .anthropic, now: start.addingTimeInterval(hours(27))).isEmpty)
        }
    }

    @Test func providersAreKeptApartAndClearRemovesOne() {
        withIsolatedDefaults { defaults in
            let store = UserDefaultsUsageHistoryStore(defaults: defaults)

            store.record(report([("session", 10)]), provider: .anthropic, at: start)
            store.record(report([("cycle", 20)]), provider: .cursor, at: start)
            store.clear(provider: .anthropic)

            #expect(store.samples(provider: .anthropic, now: start).isEmpty)
            #expect(store.samples(provider: .cursor, now: start)["cycle"] == [UsageSample(date: start, percent: 20)])
        }
    }

    @Test func corruptDataReadsAsEmptyAndIsReplacedOnWrite() {
        withIsolatedDefaults { defaults in
            let store = UserDefaultsUsageHistoryStore(defaults: defaults)

            defaults.set("garbage", forKey: "history.anthropic")
            #expect(store.samples(provider: .anthropic, now: start).isEmpty)

            defaults.set(["session": "not data"], forKey: "history.anthropic")
            #expect(store.samples(provider: .anthropic, now: start).isEmpty)

            store.record(report([("session", 10)]), provider: .anthropic, at: start)
            #expect(store.samples(provider: .anthropic, now: start)["session"] == [UsageSample(date: start, percent: 10)])
        }
    }
}
