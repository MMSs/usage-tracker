import Foundation
import os

/// One half of one provider: the unit that has its own refresh timer.
struct RefreshTarget: Hashable, Sendable {
    let provider: Provider
    let half: Half
}

/// Fetching is pointless while the Mac is asleep or the network is down, so
/// the scheduler runs its timers only while both hold and treats any entry
/// into that state as a reason to refresh straight away. Each scheduled
/// target has its own timer and interval.
@MainActor
final class RefreshScheduler {
    typealias Refresh = @MainActor () async -> Void
    typealias TargetRefresh = @MainActor (RefreshTarget) async -> Void
    typealias Sleep = @MainActor (Duration) async -> Void

    private let initialRefresh: Refresh
    private let periodicRefresh: TargetRefresh
    private let sleep: Sleep
    private let sleepObserver: SystemSleepObserving
    private let networkObserver: NetworkReachabilityObserving

    private var schedules: [RefreshTarget: RefreshInterval]
    private var isAwake = true
    private var isOnline = true
    private var isStarted = false
    private var initialRefreshTask: Task<Void, Never>?
    private var periodicTasks: [RefreshTarget: Task<Void, Never>] = [:]

    init(
        schedules: [RefreshTarget: RefreshInterval],
        initialRefresh: @escaping Refresh,
        periodicRefresh: @escaping TargetRefresh,
        sleepObserver: SystemSleepObserving,
        networkObserver: NetworkReachabilityObserving,
        sleep: @escaping Sleep = { duration in
            try? await Task.sleep(for: duration)
        }
    ) {
        self.schedules = schedules
        self.initialRefresh = initialRefresh
        self.periodicRefresh = periodicRefresh
        self.sleepObserver = sleepObserver
        self.networkObserver = networkObserver
        self.sleep = sleep
    }

    func start() {
        guard !isStarted else {
            return
        }

        isStarted = true
        Log.scheduler.debug("started")

        initialRefreshTask = Task {
            await initialRefresh()
        }

        sleepObserver.startObserving(
            onSleep: { [weak self] in
                self?.setAwake(false)
            },
            onWake: { [weak self] in
                self?.setAwake(true)
            }
        )
        networkObserver.startObserving { [weak self] isOnline in
            self?.setOnline(isOnline)
        }

        startAllCycles(refreshingImmediately: false)
    }

    func stop() {
        sleepObserver.stopObserving()
        networkObserver.stopObserving()
        initialRefreshTask?.cancel()
        initialRefreshTask = nil
        cancelAllCycles()
        isStarted = false
        Log.scheduler.debug("stopped")
    }

    /// Nil removes the target's timer. A change restarts only that target's countdown.
    func setSchedule(_ interval: RefreshInterval?, for target: RefreshTarget) {
        guard interval != schedules[target] else {
            return
        }

        schedules[target] = interval
        Log.scheduler.debug("\(target.provider.rawValue, privacy: .public) \(target.half.rawValue, privacy: .public): interval \(interval.map { "\($0.duration)" } ?? "off", privacy: .public)")

        guard isStarted, isActive else {
            return
        }

        cancelCycle(for: target)
        if let interval {
            startCycle(for: target, interval: interval, refreshingImmediately: false)
        }
    }

    private var isActive: Bool {
        isAwake && isOnline
    }

    private func setAwake(_ isAwake: Bool) {
        guard isAwake != self.isAwake else {
            return
        }

        let wasActive = isActive
        self.isAwake = isAwake
        Log.scheduler.debug("\(isAwake ? "woke" : "sleeping", privacy: .public)")
        applyActivityChange(wasActive: wasActive)
    }

    private func setOnline(_ isOnline: Bool) {
        guard isOnline != self.isOnline else {
            return
        }

        let wasActive = isActive
        self.isOnline = isOnline
        Log.scheduler.debug("\(isOnline ? "online" : "offline", privacy: .public)")
        applyActivityChange(wasActive: wasActive)
    }

    private func applyActivityChange(wasActive: Bool) {
        guard isStarted, wasActive != isActive else {
            return
        }

        guard isActive else {
            Log.scheduler.debug("paused: refreshes wait for wake and network")
            cancelAllCycles()
            return
        }

        Log.scheduler.debug("resumed: refreshing now")
        startAllCycles(refreshingImmediately: true)
    }

    private func startAllCycles(refreshingImmediately: Bool) {
        cancelAllCycles()

        guard isActive else {
            return
        }

        for (target, interval) in schedules {
            startCycle(for: target, interval: interval, refreshingImmediately: refreshingImmediately)
        }
    }

    private func startCycle(for target: RefreshTarget, interval: RefreshInterval, refreshingImmediately: Bool) {
        let duration = interval.duration
        let periodicRefresh = periodicRefresh
        let sleep = sleep

        periodicTasks[target] = Task {
            if refreshingImmediately {
                await periodicRefresh(target)

                guard !Task.isCancelled else {
                    return
                }
            }

            while !Task.isCancelled {
                await sleep(duration)

                guard !Task.isCancelled else {
                    return
                }

                Log.scheduler.debug("\(target.provider.rawValue, privacy: .public) \(target.half.rawValue, privacy: .public): tick")
                await periodicRefresh(target)
            }
        }
    }

    private func cancelCycle(for target: RefreshTarget) {
        periodicTasks[target]?.cancel()
        periodicTasks[target] = nil
    }

    private func cancelAllCycles() {
        periodicTasks.values.forEach { $0.cancel() }
        periodicTasks.removeAll()
    }
}
