import AppKit
import SwiftUI

/// Shows or hides the Dock icon by switching the activation policy.
@MainActor
protocol DockPresenting {
    func setVisible(_ visible: Bool)
}

struct AppDockPresence: DockPresenting {
    func setVisible(_ visible: Bool) {
        NSApp.setActivationPolicy(visible ? .regular : .accessory)
    }
}

/// Owns the Settings window. The app is in the Dock while it is open and
/// leaves when it closes. A new window is built for each opening so the
/// fields' disappearance commits any pending draft.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let dock: DockPresenting
    let selection = SettingsSelection()
    private(set) var window: NSWindow?

    init(model: AppModel, dock: DockPresenting) {
        self.model = model
        self.dock = dock
    }

    func present(_ request: SettingsRequest) {
        selection.apply(request, listed: model.providers.filter(\.hasAnyHalf).map(\.id))

        let window = self.window ?? makeWindow()
        self.window = window

        dock.setVisible(true)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window?.delegate = nil
        window = nil
        dock.setVisible(false)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 440),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: SettingsView(appModel: model, selection: selection))
        window.setFrameAutosaveName("Settings")
        window.center()
        window.delegate = self
        return window
    }
}
