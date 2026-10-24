import Foundation

/// Fetching is pointless while the Mac is asleep or the network is down, so
/// the scheduler runs its timers only while both hold and treats any entry
/// into that state as a reason to refresh straight away. Each scheduled
/// provider has its own timer and interval.
@MainActor
final class RefreshScheduler {
    typealias Refresh = @MainActor () async -> Void
    typealias ProviderRefresh = @MainActor (Provider) async -> Void
    typealias Sleep = @MainActor (Duration) async -> Void

    private let initialRefresh: Refresh
    private let periodicRefresh: ProviderRefresh
    private let sleep: Sleep
    private let sleepObserver: SystemSleepObserving
    private let networkObserver: NetworkReachabilityObserving

    private var schedules: [Provider: RefreshInterval]
    private var isAwake = true
    private var isOnline = true
    private var isStarted = false
    private var initialRefreshTask: Task<Void, Never>?
    private var periodicTasks: [Provider: Task<Void, Never>] = [:]

    init(
        schedules: [Provider: RefreshInterval],
        initialRefresh: @escaping Refresh,
        periodicRefresh: @escaping ProviderRefresh,
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
    }

    /// Nil removes the provider's timer. A change restarts only that provider's countdown.
    func setSchedule(_ interval: RefreshInterval?, for provider: Provider) {
        guard interval != schedules[provider] else {
            return
        }

        schedules[provider] = interval

        guard isStarted, isActive else {
            return
        }

        cancelCycle(for: provider)
        if let interval {
            startCycle(for: provider, interval: interval, refreshingImmediately: false)
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
        applyActivityChange(wasActive: wasActive)
    }

    private func setOnline(_ isOnline: Bool) {
        guard isOnline != self.isOnline else {
            return
        }

        let wasActive = isActive
        self.isOnline = isOnline
        applyActivityChange(wasActive: wasActive)
    }

    private func applyActivityChange(wasActive: Bool) {
        guard isStarted, wasActive != isActive else {
            return
        }

        guard isActive else {
            cancelAllCycles()
            return
        }

        startAllCycles(refreshingImmediately: true)
    }

    private func startAllCycles(refreshingImmediately: Bool) {
        cancelAllCycles()

        guard isActive else {
            return
        }

        for (provider, interval) in schedules {
            startCycle(for: provider, interval: interval, refreshingImmediately: refreshingImmediately)
        }
    }

    private func startCycle(for provider: Provider, interval: RefreshInterval, refreshingImmediately: Bool) {
        let duration = interval.duration
        let periodicRefresh = periodicRefresh
        let sleep = sleep

        periodicTasks[provider] = Task {
            if refreshingImmediately {
                await periodicRefresh(provider)

                guard !Task.isCancelled else {
                    return
                }
            }

            while !Task.isCancelled {
                await sleep(duration)

                guard !Task.isCancelled else {
                    return
                }

                await periodicRefresh(provider)
            }
        }
    }

    private func cancelCycle(for provider: Provider) {
        periodicTasks[provider]?.cancel()
        periodicTasks[provider] = nil
    }

    private func cancelAllCycles() {
        periodicTasks.values.forEach { $0.cancel() }
        periodicTasks.removeAll()
    }
}
