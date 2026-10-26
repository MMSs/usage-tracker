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
        AboutPanel.replaceAboutItem(in: NSApp.mainMenu)
        aboutObserver = AboutPanel.MenuTrackingObserver { NSApp.mainMenu }
    }

    /// Finder, Spotlight or the Dock icon: bring Settings forward without changing the page.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow.showKeepingSelection()
        return false
    }
}
