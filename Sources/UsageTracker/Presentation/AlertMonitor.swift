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

    /// Always records crossings, even when `delivers` is false, so turning
    /// alerts on does not flood with everything already over a threshold.
    func evaluate(_ measures: [AlertMeasure], delivers: Bool) {
        for measure in measures {
            let reached = AlertPolicy.thresholds.filter { measure.percent >= Double($0) }

            // Falling back below a threshold re-arms it.
            for threshold in AlertPolicy.thresholds where !reached.contains(threshold) {
                store.clearDelivered("\(measure.id).\(threshold)")
            }

            guard let highest = reached.max() else {
                continue
            }

            let fresh = reached.contains { !store.hasDelivered("\(measure.id).\($0)") }
            for threshold in reached {
                store.markDelivered("\(measure.id).\(threshold)")
            }

            if fresh, delivers {
                notifier.deliver(AlertPolicy.alert(for: measure, threshold: highest))
            }
        }
    }
}
