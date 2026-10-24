import Testing
@testable import UsageTracker

@Suite struct RefreshIntervalTests {
    @Test func everyStepMapsToItsDuration() {
        #expect(RefreshInterval.allCases.map(\.seconds) == [30, 60, 120, 300, 600, 900, 1200, 1800, 3600])
        #expect(RefreshInterval.thirtySeconds.duration == .seconds(30))
        #expect(RefreshInterval.oneHour.duration == .seconds(3600))
    }

    @Test func theDefaultPreservesTheHistoricFiveMinuteCadence() {
        #expect(RefreshInterval.default == .fiveMinutes)
    }

    @Test func theStepsAreOfferedShortestFirst() {
        #expect(RefreshInterval.allCases == [
            .thirtySeconds, .oneMinute, .twoMinutes, .fiveMinutes, .tenMinutes,
            .fifteenMinutes, .twentyMinutes, .thirtyMinutes, .oneHour,
        ])
    }

    @Test func everyStepHasATitle() {
        #expect(RefreshInterval.allCases.map(\.title) == ["30 s", "1 min", "2 min", "5 min", "10 min", "15 min", "20 min", "30 min", "1 hour"])
    }

    @Test func sliderValuesRoundToTheNearestStepAndClamp() {
        #expect(RefreshInterval.fiveMinutes.step == 3)
        #expect(RefreshInterval.at(step: 3.4) == .fiveMinutes)
        #expect(RefreshInterval.at(step: 3.6) == .tenMinutes)
        #expect(RefreshInterval.at(step: -2) == .thirtySeconds)
        #expect(RefreshInterval.at(step: 40) == .oneHour)
    }
}
