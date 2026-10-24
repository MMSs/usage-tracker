import AppKit

@MainActor
protocol SystemSleepObserving {
    func startObserving(
        onSleep: @escaping @MainActor @Sendable () -> Void,
        onWake: @escaping @MainActor @Sendable () -> Void
    )
    func stopObserving()
}

/// `NSWorkspace` reports system sleep, not display sleep or screen lock, which
/// is the distinction the app wants: fetching is pointless only when the
/// machine itself is down.
@MainActor
final class SystemSleepObserver: SystemSleepObserving {
    private var observers: [NSObjectProtocol] = []

    func startObserving(
        onSleep: @escaping @MainActor @Sendable () -> Void,
        onWake: @escaping @MainActor @Sendable () -> Void
    ) {
        guard observers.isEmpty else {
            return
        }

        let center = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    onSleep()
                }
            },
            center.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    onWake()
                }
            },
        ]
    }

    func stopObserving() {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver(_:))
        observers.removeAll()
    }
}
