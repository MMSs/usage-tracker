import AppKit
import SwiftUI

/// Shows or hides the Dock icon by switching the activation policy, and
/// brings the app forward.
@MainActor
protocol DockPresenting {
    func setVisible(_ visible: Bool)
    func activate()
}

struct AppDockPresence: DockPresenting {
    func setVisible(_ visible: Bool) {
        NSApp.setActivationPolicy(visible ? .regular : .accessory)
    }

    func activate() {
        NSApp.activate()
    }
}

/// Owns the Settings window. The app is in the Dock while it is open and
/// leaves when it closes. A new window is built for each opening so the
/// fields' disappearance commits any pending draft.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let dock: DockPresenting
    /// Nil keeps the frame out of user defaults (tests).
    private let frameAutosaveName: String?
    let selection = SettingsSelection()
    private(set) var window: NSWindow?

    init(model: AppModel, dock: DockPresenting, frameAutosaveName: String? = "Settings") {
        self.model = model
        self.dock = dock
        self.frameAutosaveName = frameAutosaveName
    }

    func present(_ request: SettingsRequest) {
        selection.apply(request, listed: model.providers.filter(\.hasAnyHalf).map(\.id))
        show()
    }

    /// Brings the window forward, keeping the page the user is on; opens on General when there is none.
    func showKeepingSelection() {
        if window == nil {
            selection.apply(.general, listed: [])
        }
        show()
    }

    private func show() {
        let window = self.window ?? makeWindow()
        self.window = window

        dock.setVisible(true)
        dock.activate()
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
        let host = NSHostingController(rootView: SettingsView(appModel: model, selection: selection))
        // Left to itself the host resizes the window to the view's ideal size; the window owns its size instead.
        host.sizingOptions = []
        window.contentViewController = host
        window.contentMinSize = NSSize(width: 580, height: 400)
        window.setContentSize(NSSize(width: 640, height: 440))
        if let frameAutosaveName, window.setFrameUsingName(frameAutosaveName) {
            window.setFrameAutosaveName(frameAutosaveName)
        } else {
            if let frameAutosaveName {
                window.setFrameAutosaveName(frameAutosaveName)
            }
            window.center()
        }
        window.delegate = self
        return window
    }
}
