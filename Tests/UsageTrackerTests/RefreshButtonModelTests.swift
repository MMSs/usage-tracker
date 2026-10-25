import Foundation
import Testing
@testable import UsageTracker

@Suite @MainActor struct RefreshButtonModelTests {
    private final class Clock {
        var date = Date(timeIntervalSince1970: 1_000_000)
    }

    private let clock = Clock()
    private let sleeper = ControllableSleeper()

    private func makeModel() -> RefreshButtonModel {
        RefreshButtonModel(
            sleep: { [sleeper] duration in await sleeper.sleep(duration) },
            now: { [clock] in clock.date }
        )
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            await Task.yield()
        }
    }

    @Test func closingThePanelLeavesAClickedRefreshRunning() async {
        let model = makeModel()
        let gate = SuspendedGate()
        var finished = false
        var cancelled = false

        model.click {
            await gate.wait()
            cancelled = Task.isCancelled
            finished = true
            return true
        }
        await Task.yield()
        model.panelClosed()
        gate.resume()
        await waitUntil { finished && model.feedback.phase == .succeeded }

        #expect(finished)
        #expect(!cancelled)
        #expect(model.feedback.phase == .succeeded)
        sleeper.resume()
    }

    @Test func theResultLapsesAfterItsTime() async {
        let model = makeModel()

        model.click { false }
        await sleeper.waitForSleepCount(1)

        #expect(model.feedback.phase == .failed)
        #expect(sleeper.durations == [.seconds(RefreshFeedback.resultDuration)])

        clock.date.addTimeInterval(RefreshFeedback.resultDuration)
        sleeper.resume()
        await waitUntil { model.feedback.phase == .idle }

        #expect(model.feedback.phase == .idle)
    }

    @Test func closingThePanelStopsTheLapseTimer() async {
        let model = makeModel()

        model.click { true }
        await sleeper.waitForSleepCount(1)
        model.panelClosed()
        clock.date.addTimeInterval(RefreshFeedback.resultDuration)
        sleeper.resume()
        for _ in 0..<20 {
            await Task.yield()
        }

        // The timer did not idle it; the drawn phase still lapses by the clock.
        #expect(model.feedback.phase == .succeeded)
        #expect(model.feedback.displayed(at: clock.date) == .idle)
    }

    @Test func aClickWhileOneRunsIsIgnored() async {
        let model = makeModel()
        let gate = SuspendedGate()
        var calls = 0

        let first = model.click {
            calls += 1
            await gate.wait()
            return true
        }
        let second = model.click {
            calls += 1
            return true
        }
        await Task.yield()

        #expect(first)
        #expect(!second)
        gate.resume()
        await waitUntil { model.feedback.phase == .succeeded }
        #expect(calls == 1)
        sleeper.resume()
    }
}
