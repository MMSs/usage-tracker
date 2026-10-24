import Foundation

/// Open at login: the user's switch, the live macOS status, and the launch rule.
///
/// The stored preference is only ever set to on after a registration
/// succeeded (or macOS already had the item enabled), so "preference on but
/// status not registered" can only mean the user removed the item in System
/// Settings. That is read as turning it off and never re-registered. The same
/// goes the other way: an item enabled in System Settings turns the switch on.
/// With no stored preference, the first launch registers once.
@MainActor
final class LoginItemModel: ObservableObject {
    @Published private(set) var status: LoginItemStatus
    @Published private(set) var isOn: Bool
    /// The last register or unregister failure, until the next attempt or refresh.
    @Published private(set) var failure: String?

    private let manager: LoginItemManaging
    private let store: LoginItemPreferenceStoring

    init(manager: LoginItemManaging, store: LoginItemPreferenceStoring) {
        self.manager = manager
        self.store = store
        status = manager.status
        isOn = store.preference() ?? false
    }

    /// Whether the user must allow the item in System Settings.
    var needsApproval: Bool {
        status == .requiresApproval
    }

    /// One line under the switch: the failure, else what the live status means.
    var statusLine: String? {
        if let failure {
            return failure
        }

        switch status {
        case .enabled: return "Opens when you log in"
        case .requiresApproval: return "Needs approval in System Settings"
        case .notFound: return "macOS can't find the app. Open the copy in Applications."
        case .notRegistered: return nil
        }
    }

    func reconcileAtLaunch() {
        guard store.preference() == nil else {
            reconcile()
            return
        }

        status = manager.status
        Log.loginItem.info("first launch, status \(self.status.rawValue, privacy: .public)")
        if holdsItem {
            // Registered already (possibly awaiting approval): adopt it, registering again would throw.
            remember(true)
            return
        }

        // Stays unset on failure, so the next launch tries again.
        attempt(register: true)
    }

    /// Re-reads the status, for when the Settings window appears or the app
    /// comes back from System Settings.
    func refresh() {
        failure = nil
        reconcile()
    }

    func setOn(_ isOn: Bool) {
        status = manager.status
        Log.loginItem.info("switch \(isOn ? "on" : "off", privacy: .public), status \(self.status.rawValue, privacy: .public)")
        attempt(register: isOn)
    }

    func openSystemSettings() {
        manager.openSystemSettings()
    }

    private func reconcile() {
        status = manager.status
        let preference = store.preference()
        Log.loginItem.info("status \(self.status.rawValue, privacy: .public), preference \(String(describing: preference), privacy: .public)")

        switch (preference, status) {
        case (true, .notRegistered):
            Log.loginItem.info("removed in System Settings, keeping it off")
            remember(false)
        case (false, .enabled):
            Log.loginItem.info("added in System Settings, switching on")
            remember(true)
        default:
            isOn = preference ?? false
        }
    }

    /// Whether macOS already has the item, enabled or waiting for approval.
    private var holdsItem: Bool {
        status == .enabled || status == .requiresApproval
    }

    private func attempt(register: Bool) {
        let verb = register ? "register" : "unregister"
        do {
            if register {
                if !holdsItem {
                    try manager.register()
                }
            } else if status != .notRegistered, status != .notFound {
                try manager.unregister()
            }

            status = manager.status
            Log.loginItem.info("\(verb, privacy: .public) done, status \(self.status.rawValue, privacy: .public)")

            // A register that returned without the item appearing is a failure, not a preference.
            if register, !holdsItem {
                failure = "Couldn't turn on Open at login: macOS did not register the app (\(status.rawValue))."
                Log.loginItem.error("register returned but status is \(self.status.rawValue, privacy: .public)")
                return
            }

            failure = nil
            remember(register)
        } catch {
            let error = error as NSError
            Log.loginItem.error("\(verb, privacy: .public) failed, \(error.domain, privacy: .public) \(error.code, privacy: .public): \(error.localizedDescription, privacy: .public)")
            status = manager.status
            failure = "Couldn't turn \(register ? "on" : "off") Open at login: \(error.localizedDescription)"
        }
    }

    private func remember(_ isOn: Bool) {
        store.setPreference(isOn)
        self.isOn = isOn
    }
}
