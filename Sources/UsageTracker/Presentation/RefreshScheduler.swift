import Foundation

/// Fetching is pointless while the Mac is asleep or the network is down, so
/// the scheduler runs its timer only while both hold and treats any entry into
/// that state as a reason to refresh straight away.
@MainActor
final class RefreshScheduler {
    typealias Refresh = @MainActor () async -> Void
    typealias Sleep = @MainActor (Duration) async -> Void

    private let initialRefresh: Refresh
    private let periodicRefresh: Refresh
    private let sleep: Sleep
    private let sleepObserver: SystemSleepObserving
    private let networkObserver: NetworkReachabilityObserving

    private var interval: RefreshInterval
    private var isAwake = true
    private var isOnline = true
    private var isStarted = false
    private var initialRefreshTask: Task<Void, Never>?
    private var periodicRefreshTask: Task<Void, Never>?

    init(
        interval: RefreshInterval,
        initialRefresh: @escaping Refresh,
        periodicRefresh: @escaping Refresh,
        sleepObserver: SystemSleepObserving,
        networkObserver: NetworkReachabilityObserving,
        sleep: @escaping Sleep = { duration in
            try? await Task.sleep(for: duration)
        }
    ) {
        self.interval = interval
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

        startPeriodicCycle(refreshingImmediately: false)
    }

    func stop() {
        sleepObserver.stopObserving()
        networkObserver.stopObserving()
        initialRefreshTask?.cancel()
        initialRefreshTask = nil
        cancelPeriodicCycle()
        isStarted = false
    }

    func setInterval(_ interval: RefreshInterval) {
        guard interval != self.interval else {
            return
        }

        self.interval = interval

        guard isStarted, isActive else {
            return
        }

        startPeriodicCycle(refreshingImmediately: false)
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
            cancelPeriodicCycle()
            return
        }

        startPeriodicCycle(refreshingImmediately: true)
    }

    private func startPeriodicCycle(refreshingImmediately: Bool) {
        cancelPeriodicCycle()

        guard isActive else {
            return
        }

        let duration = interval.duration
        let periodicRefresh = periodicRefresh
        let sleep = sleep

        periodicRefreshTask = Task {
            if refreshingImmediately {
                await periodicRefresh()

                guard !Task.isCancelled else {
                    return
                }
            }

            while !Task.isCancelled {
                await sleep(duration)

                guard !Task.isCancelled else {
                    return
                }

                await periodicRefresh()
            }
        }
    }

    private func cancelPeriodicCycle() {
        periodicRefreshTask?.cancel()
        periodicRefreshTask = nil
    }
}
