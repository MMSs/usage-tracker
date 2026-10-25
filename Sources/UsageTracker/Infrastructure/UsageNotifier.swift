import Foundation
@preconcurrency import UserNotifications

@MainActor
protocol UsageNotifying {
    func deliver(_ alert: UsageAlert)
    /// Asks macOS for permission to post alerts, which lists the app in
    /// System Settings › Notifications. Safe to call again.
    func requestAuthorization()
}

/// Posts alerts through the notification center. Authorization is requested
/// at launch and again before each delivery.
@MainActor
final class SystemUsageNotifier: NSObject, UsageNotifying, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func deliver(_ alert: UsageAlert) {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        let request = UNNotificationRequest(identifier: alert.key, content: content, trigger: nil)
        let center = center

        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else {
                return
            }

            center.add(request)
        }
    }

    /// Menu bar apps are always "frontmost" while the popover is open; show
    /// banners anyway.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

/// The master alert switch, the switch of each kind, and the keys of alerts
/// already delivered.
protocol AlertStateStoring: AnyObject {
    var isEnabled: Bool { get set }
    func isEnabled(_ kind: AlertKind) -> Bool
    func setEnabled(_ enabled: Bool, for kind: AlertKind)
    func hasDelivered(_ key: String) -> Bool
    func markDelivered(_ key: String)
    func clearDelivered(_ key: String)
}

final class UserDefaultsAlertStateStore: AlertStateStoring {
    private static let enabledKey = "alerts.enabled"
    private static let deliveredKey = "alerts.delivered"
    /// Keys name a window run or spend period, so older ones can be forgotten.
    private static let maxDelivered = 200

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        get { defaults.object(forKey: Self.enabledKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    func isEnabled(_ kind: AlertKind) -> Bool {
        defaults.object(forKey: Self.kindKey(kind)) as? Bool ?? kind.defaultEnabled
    }

    func setEnabled(_ enabled: Bool, for kind: AlertKind) {
        defaults.set(enabled, forKey: Self.kindKey(kind))
    }

    private static func kindKey(_ kind: AlertKind) -> String {
        "alerts.kind.\(kind.rawValue)"
    }

    func hasDelivered(_ key: String) -> Bool {
        delivered.contains(key)
    }

    func markDelivered(_ key: String) {
        delivered = Array((delivered + [key]).suffix(Self.maxDelivered))
    }

    func clearDelivered(_ key: String) {
        delivered.removeAll { $0 == key }
    }

    private var delivered: [String] {
        get { defaults.stringArray(forKey: Self.deliveredKey) ?? [] }
        set { defaults.set(newValue, forKey: Self.deliveredKey) }
    }
}
