import Foundation
import Network

@MainActor
protocol NetworkReachabilityObserving {
    func startObserving(onChange: @escaping @MainActor @Sendable (Bool) -> Void)
    func stopObserving()
}

@MainActor
final class NetworkReachabilityObserver: NetworkReachabilityObserving {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.mohab.usage-tracker.reachability")
    private var isObserving = false
    private var lastReport: Bool?

    func startObserving(onChange: @escaping @MainActor @Sendable (Bool) -> Void) {
        guard !isObserving else {
            return
        }

        isObserving = true
        monitor.pathUpdateHandler = { [weak self] path in
            let isOnline = path.status == .satisfied

            Task { @MainActor in
                self?.report(isOnline, to: onChange)
            }
        }
        monitor.start(queue: queue)
    }

    func stopObserving() {
        monitor.pathUpdateHandler = nil
        monitor.cancel()
        isObserving = false
        lastReport = nil
    }

    /// `NWPathMonitor` republishes the same status on unrelated path changes,
    /// such as switching between Wi-Fi networks that are both online.
    private func report(_ isOnline: Bool, to onChange: @MainActor @Sendable (Bool) -> Void) {
        guard isObserving, lastReport != isOnline else {
            return
        }

        lastReport = isOnline
        onChange(isOnline)
    }
}
