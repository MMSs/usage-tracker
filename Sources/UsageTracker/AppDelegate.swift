import AppKit

/// Owns the model and the Settings window. A launch only puts the items in
/// the menu bar; reopening the running app (Finder, Spotlight, the Dock)
/// brings up Settings.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let model: AppModel
    private let settingsWindow: SettingsWindowController
    private var aboutObserver: AboutPanel.MenuTrackingObserver?

    override init() {
        model = AppModel.live()
        settingsWindow = SettingsWindowController(model: model, dock: AppDockPresence())
        super.init()
        model.presentSettings = { [settingsWindow] request in settingsWindow.present(request) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.loginItem.reconcileAtLaunch()
        // iCloud tells the app about another Mac's change with a silent push.
        // Without the push entitlement this fails quietly and pulls at each refresh still catch up.
        if model.sync?.isAvailable(.settingsOnly) == true {
            NSApp.registerForRemoteNotifications()
        }
        AboutPanel.replaceAboutItem(in: NSApp.mainMenu)
        aboutObserver = AboutPanel.MenuTrackingObserver { NSApp.mainMenu }
    }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        Task { await model.sync?.pull() }
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        Log.sync.notice("no push for sync: \(String(describing: type(of: error)), privacy: .public)")
    }

    /// Finder, Spotlight or the Dock icon: bring Settings forward without changing the page.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow.showKeepingSelection()
        return false
    }
}
