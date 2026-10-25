import Foundation
import Testing
@testable import UsageTracker

@MainActor
@Suite struct RefreshSchedulerTests {
    private let cursorPlan = RefreshTarget(provider: .cursor, half: .subscription)
    private let anthropicAPI = RefreshTarget(provider: .anthropic, half: .api)

    @Test func periodicSchedulingStartsBeforeTheInitialRefreshCompletes() async {
        let initialRefresh = SuspendedRefresh()
        let context = SchedulerContext(initialRefresh: initialRefresh.refresh)

        context.scheduler.start()
        await initialRefresh.waitUntilStarted()
        await context.sleeper.waitForSleepCount(1)
        context.sleeper.resume()
        await context.periodicRefresh.waitForCallCount(1)

        #expect(!initialRefresh.hasCompleted)

        context.tearDown()
        initialRefresh.resume()
    }

    @Test func theConfiguredIntervalDrivesTheWait() async {
        let context = SchedulerContext(schedules: [cursorPlan: .oneMinute])

        context.scheduler.start()
        await context.sleeper.waitForSleepCount(1)

        #expect(context.sleeper.durations == [.seconds(60)])

        context.tearDown()
    }

    @Test func sleepingTheMacStopsTheCycleWithoutRefreshing() async {
        let context = SchedulerContext()

        context.scheduler.start()
        await context.sleeper.waitForSleepCount(1)

        context.sleepObserver.sendSleep()
        context.sleeper.resume()
        await settle()

        #expect(context.periodicRefresh.callCount == 0)
        #expect(context.sleeper.durations == [.seconds(300)])

        context.tearDown()
    }

    @Test func wakingRefreshesImmediatelyAndRestartsTheCountdown() async {
        let context = SchedulerContext()

        context.scheduler.start()
        await context.sleeper.waitForSleepCount(1)
        context.sleepObserver.sendSleep()
        context.sleeper.resume()
        await settle()

        context.sleepObserver.sendWake()
        await context.periodicRefresh.waitForCallCount(1)
        await context.sleeper.waitForSleepCount(2)

        #expect(context.periodicRefresh.callCount == 1)
        #expect(context.sleeper.durations == [.seconds(300), .seconds(300)])

        context.tearDown()
    }

    @Test func losingTheNetworkStopsTheCycleWithoutRefreshing() async {
        let context = SchedulerContext()

        context.scheduler.start()
        await context.sleeper.waitForSleepCount(1)

        context.networkObserver.send(isOnline: false)
        context.sleeper.resume()
        await settle()

        #expect(context.periodicRefresh.callCount == 0)
        #expect(context.sleeper.durations == [.seconds(300)])

        context.tearDown()
    }

    @Test func reconnectingRefreshesImmediatelyAndRestartsTheCountdown() async {
        let context = SchedulerContext()

        context.scheduler.start()
        await context.sleeper.waitForSleepCount(1)
        context.networkObserver.send(isOnline: false)
        context.sleeper.resume()
        await settle()

        context.networkObserver.send(isOnline: true)
        await context.periodicRefresh.waitForCallCount(1)
        await context.sleeper.waitForSleepCount(2)

        #expect(context.periodicRefresh.callCount == 1)

        context.tearDown()
    }

    @Test func wakingAndReconnectingTogetherRefreshOnlyOnce() async {
        let context = SchedulerContext()

        context.scheduler.start()
        await context.sleeper.waitForSleepCount(1)
        context.sleepObserver.sendSleep()
        context.networkObserver.send(isOnline: false)
        context.sleeper.resume()
        await settle()

        context.sleepObserver.sendWake()
        context.networkObserver.send(isOnline: true)
        await context.periodicRefresh.waitForCallCount(1)
        await settle()

        #expect(context.periodicRefresh.callCount == 1)

        context.tearDown()
    }

    @Test func aFirstOnlineReportIsNotTreatedAsAReconnect() async {
        let context = SchedulerContext()

        context.scheduler.start()
        await context.sleeper.waitForSleepCount(1)

        context.networkObserver.send(isOnline: true)
        await settle()

        #expect(context.periodicRefresh.callCount == 0)
        #expect(context.sleeper.durations == [.seconds(300)])

        context.tearDown()
    }

    @Test func changingTheIntervalReschedulesWithoutRefreshing() async {
        let context = SchedulerContext()

        context.scheduler.start()
        await context.sleeper.waitForSleepCount(1)

        context.scheduler.setSchedule(.oneHour, for: cursorPlan)
        await context.sleeper.waitForSleepCount(2)
        await settle()

        #expect(context.periodicRefresh.callCount == 0)
        #expect(context.sleeper.durations == [.seconds(300), .seconds(3600)])

        context.tearDown()
    }

    @Test func eachTargetTicksOnItsOwnInterval() async {
        let context = SchedulerContext(schedules: [cursorPlan: .oneMinute, anthropicAPI: .oneHour])

        context.scheduler.start()
        await context.sleeper.waitForSleepCount(2)

        #expect(Set(context.sleeper.durations) == [.seconds(60), .seconds(3600)])

        context.sleeper.resume()
        await context.periodicRefresh.waitForCallCount(2)

        #expect(Set(context.periodicRefresh.targets) == [cursorPlan, anthropicAPI])

        context.tearDown()
    }

    @Test func theHalvesOfOneProviderKeepSeparateTimers() async {
        let anthropicPlan = RefreshTarget(provider: .anthropic, half: .subscription)
        let context = SchedulerContext(schedules: [anthropicPlan: .thirtySeconds, anthropicAPI: .tenMinutes])

        context.scheduler.start()
        await context.sleeper.waitForSleepCount(2)

        #expect(Set(context.sleeper.durations) == [.seconds(30), .seconds(600)])

        context.tearDown()
    }

    @Test func removingATargetStopsOnlyIt() async {
        let context = SchedulerContext(schedules: [cursorPlan: .oneMinute, anthropicAPI: .oneHour])

        context.scheduler.start()
        await context.sleeper.waitForSleepCount(2)

        context.scheduler.setSchedule(nil, for: cursorPlan)
        context.sleeper.resume()
        await settle()

        #expect(context.periodicRefresh.targets == [anthropicAPI])
        #expect(context.sleeper.durations.count == 3)
        #expect(context.sleeper.durations.last == .seconds(3600))

        context.tearDown()
    }

    @Test func stoppingReleasesBothObservers() async {
        let context = SchedulerContext()

        context.scheduler.start()
        await context.sleeper.waitForSleepCount(1)

        #expect(context.sleepObserver.isObserving)
        #expect(context.networkObserver.isObserving)

        context.tearDown()

        #expect(!context.sleepObserver.isObserving)
        #expect(!context.networkObserver.isObserving)
    }
}

@MainActor
private struct SchedulerContext {
    let periodicRefresh: RefreshRecorder
    let sleeper: ControllableSleeper
    let sleepObserver: ControllableSleepObserver
    let networkObserver: ControllableNetworkObserver
    let scheduler: RefreshScheduler

    init(
        schedules: [RefreshTarget: RefreshInterval] = [RefreshTarget(provider: .cursor, half: .subscription): .fiveMinutes],
        initialRefresh: RefreshScheduler.Refresh? = nil
    ) {
        let periodicRefresh = RefreshRecorder()
        let sleeper = ControllableSleeper()
        let sleepObserver = ControllableSleepObserver()
        let networkObserver = ControllableNetworkObserver()

        self.periodicRefresh = periodicRefresh
        self.sleeper = sleeper
        self.sleepObserver = sleepObserver
        self.networkObserver = networkObserver
        scheduler = RefreshScheduler(
            schedules: schedules,
            initialRefresh: initialRefresh ?? {},
            periodicRefresh: { await periodicRefresh.refresh($0) },
            sleepObserver: sleepObserver,
            networkObserver: networkObserver,
            sleep: sleeper.sleep
        )
    }

    /// Stopping cancels the waiting task; resuming lets it observe that and
    /// exit rather than leaving a continuation dangling past the test.
    func tearDown() {
        scheduler.stop()
        sleeper.resume()
    }
}
