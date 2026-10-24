import Foundation
@testable import UsageTracker

final class MemoryProviderSettingsStore: ProviderSettingsStoring {
    private(set) var stored: [Provider: ProviderSettings]

    init(_ stored: [Provider: ProviderSettings] = [:]) {
        self.stored = stored
    }

    func settings(for provider: Provider) -> ProviderSettings {
        stored[provider] ?? .default
    }

    func setSettings(_ settings: ProviderSettings, for provider: Provider) {
        stored[provider] = settings
    }
}

@MainActor
final class ControllableSleepObserver: SystemSleepObserving {
    private var onSleep: (@MainActor @Sendable () -> Void)?
    private var onWake: (@MainActor @Sendable () -> Void)?

    var isObserving: Bool {
        onSleep != nil
    }

    func startObserving(
        onSleep: @escaping @MainActor @Sendable () -> Void,
        onWake: @escaping @MainActor @Sendable () -> Void
    ) {
        self.onSleep = onSleep
        self.onWake = onWake
    }

    func stopObserving() {
        onSleep = nil
        onWake = nil
    }

    func sendSleep() {
        onSleep?()
    }

    func sendWake() {
        onWake?()
    }
}

@MainActor
final class ControllableNetworkObserver: NetworkReachabilityObserving {
    private var onChange: (@MainActor @Sendable (Bool) -> Void)?

    var isObserving: Bool {
        onChange != nil
    }

    func startObserving(onChange: @escaping @MainActor @Sendable (Bool) -> Void) {
        self.onChange = onChange
    }

    func stopObserving() {
        onChange = nil
    }

    func send(isOnline: Bool) {
        onChange?(isOnline)
    }
}

/// Stands in for `Task.sleep`. `resume()` releases every pending sleep, so a
/// test that cancelled a cycle must call it to let the abandoned task observe
/// its cancellation and exit instead of leaking a continuation.
@MainActor
final class ControllableSleeper {
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var sleeping: [CheckedContinuation<Void, Never>] = []

    private(set) var durations: [Duration] = []

    func sleep(_ duration: Duration) async {
        durations.append(duration)
        resumeWaiters()

        await withCheckedContinuation { continuation in
            sleeping.append(continuation)
        }
    }

    func waitForSleepCount(_ count: Int) async {
        guard durations.count < count else {
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append((count, continuation))
        }
    }

    func resume() {
        let pending = sleeping
        sleeping.removeAll()
        pending.forEach { $0.resume() }
    }

    private func resumeWaiters() {
        let ready = waiters.filter { $0.count <= durations.count }
        waiters.removeAll { $0.count <= durations.count }

        ready.forEach { $0.continuation.resume() }
    }
}

@MainActor
final class RefreshRecorder {
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    private(set) var callCount = 0
    private(set) var providers: [Provider] = []

    func refresh(_ provider: Provider) async {
        providers.append(provider)
        await refresh()
    }

    func refresh() async {
        callCount += 1

        let ready = waiters.filter { $0.count <= callCount }
        waiters.removeAll { $0.count <= callCount }

        ready.forEach { $0.continuation.resume() }
    }

    func waitForCallCount(_ count: Int) async {
        guard callCount < count else {
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append((count, continuation))
        }
    }
}

@MainActor
final class SuspendedRefresh {
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var continuation: CheckedContinuation<Void, Never>?

    private(set) var hasCompleted = false

    func refresh() async {
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()

        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }

        hasCompleted = true
    }

    func waitUntilStarted() async {
        guard continuation == nil else {
            return
        }

        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

/// Lets already-scheduled main-actor work drain so a "nothing happened"
/// assertion is meaningful rather than merely premature.
@MainActor
func settle() async {
    for _ in 0..<10 {
        await Task.yield()
    }
}
