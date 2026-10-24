import Testing
@testable import UsageTracker

@Suite struct RefreshIntervalTests {
    @Test func everyChoiceMapsToItsDuration() {
        #expect(RefreshInterval.oneMinute.duration == .seconds(60))
        #expect(RefreshInterval.fiveMinutes.duration == .seconds(300))
        #expect(RefreshInterval.fifteenMinutes.duration == .seconds(900))
        #expect(RefreshInterval.oneHour.duration == .seconds(3600))
    }

    @Test func theDefaultPreservesTheHistoricFiveMinuteCadence() {
        #expect(RefreshInterval.default == .fiveMinutes)
    }

    @Test func theChoicesAreOfferedShortestFirst() {
        #expect(RefreshInterval.allCases == [.oneMinute, .fiveMinutes, .fifteenMinutes, .oneHour])
    }

    @Test func everyChoiceHasAPickerTitle() {
        #expect(RefreshInterval.allCases.map(\.title) == ["1 min", "5 min", "15 min", "1 hour"])
    }
}
