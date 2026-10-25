import Foundation

/// Turns measures into at most one alert per threshold crossing. Delivered
/// keys persist, so a relaunch does not repeat an alert.
@MainActor
final class AlertMonitor {
    private let notifier: UsageNotifying
    private let store: AlertStateStoring

    init(notifier: UsageNotifying, store: AlertStateStoring) {
        self.notifier = notifier
        self.store = store
    }

    var isEnabled: Bool {
        get { store.isEnabled }
        set { store.isEnabled = newValue }
    }

    func isEnabled(_ kind: AlertKind) -> Bool {
        store.isEnabled(kind)
    }

    func setEnabled(_ enabled: Bool, for kind: AlertKind) {
        store.setEnabled(enabled, for: kind)
    }

    func requestAuthorization() {
        notifier.requestAuthorization()
    }

    /// Always records crossings, even when `delivers` is false, so turning
    /// alerts on does not flood with everything already over a threshold.
    func evaluate(_ measures: [AlertMeasure], delivers: Bool) {
        for measure in measures {
            let reached = AlertPolicy.thresholds.filter { measure.percent >= Double($0) }

            // Falling back below a threshold re-arms it. The store is only
            // written when a key changes, not on every refresh.
            for threshold in AlertPolicy.thresholds where !reached.contains(threshold) {
                let key = "\(measure.id).\(threshold)"
                if store.hasDelivered(key) {
                    store.clearDelivered(key)
                }
            }

            guard let highest = reached.max() else {
                continue
            }

            let unmarked = reached.map { "\(measure.id).\($0)" }.filter { !store.hasDelivered($0) }
            for key in unmarked {
                store.markDelivered(key)
            }
            let fresh = !unmarked.isEmpty

            if fresh, delivers {
                notifier.deliver(AlertPolicy.alert(for: measure, threshold: highest))
            }
        }
    }
}
