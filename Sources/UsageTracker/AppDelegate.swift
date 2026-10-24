import AppKit

/// Owns the model and the Settings window; opens Settings when the user
/// launches or reopens the app, but not when the login item starts it.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let model: AppModel
    private let settingsWindow: SettingsWindowController

    override init() {
        model = AppModel.live()
        settingsWindow = SettingsWindowController(model: model, dock: AppDockPresence())
        super.init()
        model.presentSettings = { [settingsWindow] request in settingsWindow.present(request) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppStartup.configure(loginItemManager: LoginItemManager())

        if !LaunchContext.isLoginItemLaunch {
            model.presentSettings(.general)
        }
    }

    /// Finder, Spotlight or the Dock icon: bring Settings forward without changing the page.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow.showKeepingSelection()
        return false
    }
}
