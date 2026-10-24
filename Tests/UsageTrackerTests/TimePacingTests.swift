import Foundation
import Testing
@testable import UsageTracker

@Suite struct TimePacingTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let fiveHours: TimeInterval = 5 * 3600

    private func window(
        percentUsed: Double = 0,
        resetsIn: TimeInterval? = 2 * 3600,
        windowLength: TimeInterval? = 5 * 3600
    ) -> LimitWindow {
        LimitWindow(
            id: "session",
            label: "Session",
            percentUsed: percentUsed,
            resetsAt: resetsIn.map { now.addingTimeInterval($0) },
            parentID: nil,
            windowLength: windowLength
        )
    }

    @Test func idealPercentIsTheShareOfTheWindowElapsed() {
        let ideal = TimePacing.idealPercent(windowLength: fiveHours, resetsAt: now.addingTimeInterval(2 * 3600), now: now)
        #expect(abs(ideal - 60) < 0.0001)
    }

    @Test func idealPercentClampsPastTheReset() {
        let ideal = TimePacing.idealPercent(windowLength: fiveHours, resetsAt: now.addingTimeInterval(-3600), now: now)
        #expect(ideal == 100)
    }

    @Test func idealPercentClampsBeforeTheWindowStarts() {
        let ideal = TimePacing.idealPercent(windowLength: fiveHours, resetsAt: now.addingTimeInterval(6 * 3600), now: now)
        #expect(ideal == 0)
    }

    @Test func idealFractionIsTheElapsedShareForAWindow() throws {
        let fraction = try #require(TimePacing.idealFraction(for: window(), now: now))
        #expect(abs(fraction - 0.6) < 0.0001)
    }

    @Test func idealFractionIsNilWithoutLengthOrReset() {
        #expect(TimePacing.idealFraction(for: window(windowLength: nil), now: now) == nil)
        #expect(TimePacing.idealFraction(for: window(windowLength: 0), now: now) == nil)
        #expect(TimePacing.idealFraction(for: window(windowLength: -5), now: now) == nil)
        #expect(TimePacing.idealFraction(for: window(resetsIn: nil), now: now) == nil)
    }

    @Test func timeTintUsesTheOneAndOneFifteenThresholds() {
        #expect(PacingTint.forTimePacing(percentUsed: 50, idealPercent: 60) == .onPace)
        #expect(PacingTint.forTimePacing(percentUsed: 60, idealPercent: 60) == .onPace)
        #expect(PacingTint.forTimePacing(percentUsed: 65, idealPercent: 60) == .nearingLimit)
        #expect(PacingTint.forTimePacing(percentUsed: 69, idealPercent: 60) == .nearingLimit)
        #expect(PacingTint.forTimePacing(percentUsed: 70, idealPercent: 60) == .overBudget)
    }

    @Test func timeTintAtTheStartOfAWindowIsOnPaceOnlyWhenNothingIsUsed() {
        #expect(PacingTint.forTimePacing(percentUsed: 0, idealPercent: 0) == .onPace)
        #expect(PacingTint.forTimePacing(percentUsed: 1, idealPercent: 0) == .nearingLimit)
    }

    @Test func windowsTintByTimePacingWhenTheyHaveALength() {
        // 60% elapsed. The remaining-based tint would call 55 and 65 amber and 70 amber too.
        #expect(PacingTint.forWindow(window(percentUsed: 55), now: now) == .onPace)
        #expect(PacingTint.forWindow(window(percentUsed: 65), now: now) == .nearingLimit)
        #expect(PacingTint.forWindow(window(percentUsed: 70), now: now) == .overBudget)
    }

    @Test func windowsWithoutLengthFallBackToRemainingTint() {
        #expect(PacingTint.forWindow(window(percentUsed: 55, windowLength: nil), now: now) == .nearingLimit)
        #expect(PacingTint.forWindow(window(percentUsed: 10, windowLength: nil), now: now) == .onPace)
        #expect(PacingTint.forWindow(window(percentUsed: 90, windowLength: nil), now: now) == .overBudget)
        #expect(PacingTint.forWindow(window(percentUsed: 90, resetsIn: nil), now: now) == .overBudget)
    }
}
