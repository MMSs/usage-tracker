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

/// Owns the Settings window: a preferences-style window with toolbar tabs,
/// one page each, sized to the page it shows. The app is in the Dock while
/// it is open and leaves when it closes. A new window is built for each
/// opening so the fields' disappearance commits any pending draft.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let dock: DockPresenting
    /// Nil keeps the frame out of user defaults (tests).
    private let frameAutosaveName: String?
    let selection = SettingsSelection()
    private(set) var window: NSWindow?
    private var tabs: SettingsTabViewController?

    init(model: AppModel, dock: DockPresenting, frameAutosaveName: String? = "Settings") {
        self.model = model
        self.dock = dock
        self.frameAutosaveName = frameAutosaveName
    }

    private var listedProviders: [ProviderViewModel] {
        model.providers.filter(\.hasAnyHalf)
    }

    var pages: [SettingsPage] {
        [.general] + listedProviders.map { .provider($0.id) }
    }

    func present(_ request: SettingsRequest) {
        selection.apply(request, listed: listedProviders.map(\.id))
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

        tabs?.select(selection.page)
        dock.setVisible(true)
        dock.activate()
        window.makeKeyAndOrderFront(nil)
        // Activation is cooperative, so the window is also ordered front on its own.
        window.orderFrontRegardless()
        // Full keyboard access would otherwise ring the first control as soon as the window opens.
        window.makeFirstResponder(nil)
        tabs?.fitWindow(animated: false)
    }

    func windowWillClose(_ notification: Notification) {
        window?.delegate = nil
        window = nil
        tabs = nil
        dock.setVisible(false)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: SettingsLayout.pageWidth, height: 300),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .preference

        let tabs = SettingsTabViewController(pages: pages.map { page in
            (page, makePage(page))
        }, selection: selection)
        self.tabs = tabs
        tabs.select(selection.page)
        window.contentViewController = tabs

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

    private func makePage(_ page: SettingsPage) -> NSTabViewItem {
        let item: NSTabViewItem
        switch page {
        case .general:
            let host = SettingsPageController(rootView: AnyView(GeneralSettingsView(appModel: model)))
            host.title = "General"
            item = NSTabViewItem(viewController: host)
            item.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "General")
        case .provider(let id):
            let provider = model.provider(id)
            let host = SettingsPageController(rootView: AnyView(ProviderSettingsPage(provider: provider, appModel: model, selection: selection)))
            host.title = provider.descriptor.displayName
            item = NSTabViewItem(viewController: host)
            item.image = ProviderGlyphImage.toolbarImage(for: id)
        }
        item.label = item.viewController?.title ?? ""
        return item
    }
}

/// Wraps a provider page so the help request is read live from the selection.
private struct ProviderSettingsPage: View {
    @ObservedObject var provider: ProviderViewModel
    let appModel: AppModel
    @ObservedObject var selection: SettingsSelection

    var body: some View {
        ProviderSettingsView(
            provider: provider,
            appModel: appModel,
            helpFieldID: SettingsHelp.fieldID(for: provider.descriptor, helpProvider: selection.helpProvider)
        )
    }
}

/// Hosts one page and reports its ideal size so the window can follow it.
final class SettingsPageController: NSHostingController<AnyView> {
    override init(rootView: AnyView) {
        super.init(rootView: rootView)
        sizingOptions = [.preferredContentSize]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

/// Toolbar-style tabs; the window grows and shrinks to fit the selected page.
@MainActor
final class SettingsTabViewController: NSTabViewController {
    private let pages: [SettingsPage]
    private let selection: SettingsSelection
    private var sizeObservation: NSKeyValueObservation?
    /// True while the controller changes the tab itself, so the delegate does not treat it as the user's choice.
    private var isSelectingProgrammatically = false

    init(pages: [(SettingsPage, NSTabViewItem)], selection: SettingsSelection) {
        self.pages = pages.map(\.0)
        self.selection = selection
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        transitionOptions = []
        isSelectingProgrammatically = true
        for (_, item) in pages {
            addTabViewItem(item)
        }
        isSelectingProgrammatically = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    /// A page requested before the view is on screen; applied in `viewDidAppear`.
    private var pendingPage: SettingsPage?

    func select(_ page: SettingsPage) {
        guard pages.contains(page) else {
            return
        }

        guard isViewLoaded, view.window != nil else {
            pendingPage = page
            return
        }

        apply(page)
    }

    private func apply(_ page: SettingsPage) {
        guard let index = pages.firstIndex(of: page) else {
            return
        }

        isSelectingProgrammatically = true
        if index != selectedTabViewItemIndex {
            selectedTabViewItemIndex = index
        }
        isSelectingProgrammatically = false
    }

    /// Only a tab the user picked changes the selection; the initial load and
    /// programmatic changes do not.
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)

        let isUserChoice = !isSelectingProgrammatically && pendingPage == nil && view.window != nil
        if isUserChoice, selectedTabViewItemIndex >= 0 {
            let page = pages[selectedTabViewItemIndex]
            selection.page = page
            if case .provider(let id) = page, id == selection.helpProvider {
                // Keep the help open on the page it was requested for.
            } else {
                selection.helpProvider = nil
            }
        }

        observeSize(of: tabViewItem?.viewController)
        fitWindow(animated: isUserChoice)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if let pendingPage {
            self.pendingPage = nil
            apply(pendingPage)
        }
        observeSize(of: tabViewItems[selectedTabViewItemIndex].viewController)
        fitWindow(animated: false)
    }

    /// Resizes the window to the selected page, keeping its top-left corner in place.
    func fitWindow(animated: Bool) {
        guard let window = view.window,
              let controller = tabViewItems[selectedTabViewItemIndex].viewController else {
            return
        }

        let size = controller.preferredContentSize
        guard size.width > 0, size.height > 0 else {
            return
        }

        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        guard frame != window.frame else {
            return
        }

        window.setFrame(frame, display: true, animate: animated)
    }

    private func observeSize(of controller: NSViewController?) {
        sizeObservation = controller?.observe(\.preferredContentSize, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.fitWindow(animated: true)
            }
        }
    }
}

enum ProviderGlyphImage {
    /// The provider mark as a template image for toolbar tabs.
    @MainActor
    static func toolbarImage(for provider: Provider) -> NSImage? {
        // The mark sits in a padded canvas so it matches the SF Symbol tabs in size and label spacing.
        let renderer = ImageRenderer(content: ProviderGlyph(provider: provider).fill(Color.black).frame(width: 17, height: 17).frame(width: 26, height: 26))
        renderer.scale = 2
        guard let image = renderer.nsImage else {
            return nil
        }
        image.isTemplate = true
        return image
    }
}
