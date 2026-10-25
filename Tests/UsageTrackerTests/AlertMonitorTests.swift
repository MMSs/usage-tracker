import Foundation
import Testing

@testable import UsageTracker

@Suite @MainActor struct AlertMonitorTests {
    let notifier = RecordingNotifier()
    let store = MemoryAlertStateStore()

    private func measure(_ percent: Double, id: String = "anthropic.weekly.1") -> AlertMeasure {
        AlertMeasure(id: id, percent: percent, subject: "Anthropic weekly", detail: "Resets soon.")
    }

    private var monitor: AlertMonitor {
        AlertMonitor(notifier: notifier, store: store)
    }

    @Test func reachingEightyDeliversOnce() {
        let monitor = monitor

        monitor.evaluate([measure(82)], delivers: true)
        monitor.evaluate([measure(83)], delivers: true)

        #expect(notifier.delivered.map(\.key) == ["anthropic.weekly.1.80"])
    }

    @Test func jumpingPastBothDeliversOnlyNinetyFive() {
        let monitor = monitor

        monitor.evaluate([measure(97)], delivers: true)
        monitor.evaluate([measure(97)], delivers: true)

        #expect(notifier.delivered.map(\.key) == ["anthropic.weekly.1.95"])
    }

    @Test func fallingBelowReArms() {
        let monitor = monitor

        monitor.evaluate([measure(82)], delivers: true)
        monitor.evaluate([measure(50)], delivers: true)
        monitor.evaluate([measure(82)], delivers: true)

        #expect(notifier.delivered.count == 2)
    }

    @Test func aNewResetIsANewWindow() {
        let monitor = monitor

        monitor.evaluate([measure(82, id: "a.1")], delivers: true)
        monitor.evaluate([measure(82, id: "a.2")], delivers: true)

        #expect(notifier.delivered.map(\.key) == ["a.1.80", "a.2.80"])
    }

    @Test func theStoreIsWrittenOnlyWhenAKeyChanges() {
        let monitor = monitor

        monitor.evaluate([measure(10)], delivers: true)
        #expect(store.writes == 0)

        monitor.evaluate([measure(82)], delivers: true)
        monitor.evaluate([measure(83)], delivers: true)
        #expect(store.keys == ["anthropic.weekly.1.80"])
        #expect(store.writes == 1)

        monitor.evaluate([measure(50)], delivers: true)
        #expect(store.keys.isEmpty)
        #expect(store.writes == 2)
    }

    @Test func switchedOffStillMarksSoTurningOnDoesNotFlood() {
        let monitor = monitor

        monitor.evaluate([measure(82)], delivers: false)
        monitor.evaluate([measure(82)], delivers: true)

        #expect(notifier.delivered.isEmpty)
    }
}
