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
        // A provider page's tab lasts as long as its window.
        selection.tabs = [:]
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
            let host = SettingsPageController { report in
                AnyView(SettingsPageLayout(reportHeight: report) { GeneralSettingsView(appModel: self.model) })
            }
            host.title = "General"
            item = NSTabViewItem(viewController: host)
            item.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "General")
        case .provider(let id):
            let provider = model.provider(id)
            let host = SettingsPageController { report in
                AnyView(SettingsPageLayout(reportHeight: report) {
                    ProviderSettingsPage(provider: provider, appModel: self.model, selection: self.selection)
                })
            }
            host.title = provider.descriptor.displayName
            item = NSTabViewItem(viewController: host)
            item.image = ProviderGlyphImage.toolbarImage(for: id)
        }
        item.label = item.viewController?.title ?? ""
        return item
    }
}

/// Wraps a provider page so the help request and the tab are read live from the selection.
private struct ProviderSettingsPage: View {
    @ObservedObject var provider: ProviderViewModel
    let appModel: AppModel
    @ObservedObject var selection: SettingsSelection

    var body: some View {
        ProviderSettingsView(
            provider: provider,
            appModel: appModel,
            helpFieldID: SettingsHelp.fieldID(for: provider.descriptor, helpProvider: selection.helpProvider),
            tab: Binding(
                get: { selection.tabs[provider.id] },
                set: { tab in
                    if let tab {
                        selection.selectTab(tab, for: provider.id)
                    }
                }
            )
        )
    }
}

/// Hosts one page. The page reports its laid-out height, which the tab
/// controller turns into the window height; `preferredContentSize` is the
/// fallback before the first layout.
@MainActor
final class SettingsPageController: NSHostingController<AnyView> {
    private(set) var contentHeight: CGFloat = 0
    var onHeightChange: ((CGFloat) -> Void)?

    init(makeView: (@escaping (CGFloat) -> Void) -> AnyView) {
        // A box lets the view's closure reach the controller created after it.
        let box = HeightBox()
        super.init(rootView: makeView { height in box.controller?.heightChanged(height) })
        box.controller = self
        sizingOptions = [.preferredContentSize]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func heightChanged(_ height: CGFloat) {
        guard height > 0, height != contentHeight else {
            return
        }

        contentHeight = height
        onHeightChange?(height)
    }

    private final class HeightBox {
        weak var controller: SettingsPageController?
    }
}

/// Toolbar-style tabs; the window grows and shrinks to fit the selected page.
@MainActor
final class SettingsTabViewController: NSTabViewController {
    private let pages: [SettingsPage]
    private let selection: SettingsSelection
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
    /// Set while a resize is queued, so several height reports in one pass resize once.
    private var isFitQueued = false

    override func viewDidLoad() {
        super.viewDidLoad()
        for item in tabViewItems {
            (item.viewController as? SettingsPageController)?.onHeightChange = { [weak self, weak item] _ in
                guard let self, let item, self.tabViewItems.firstIndex(of: item) == self.selectedTabViewItemIndex else {
                    return
                }
                self.queueFit()
            }
        }
    }

    /// Height reports arrive inside SwiftUI's layout pass; resizing the window
    /// there re-enters layout. Resize once, on the next turn, without animation.
    private func queueFit() {
        guard !isFitQueued else {
            return
        }

        isFitQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.isFitQueued = false
            self.fitWindow(animated: false)
        }
    }

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

        fitWindow(animated: isUserChoice)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if let pendingPage {
            self.pendingPage = nil
            apply(pendingPage)
        }
        fitWindow(animated: false)
    }

    /// Resizes the window to the selected page, keeping its top-left corner in place.
    func fitWindow(animated: Bool) {
        guard let window = view.window,
              let controller = tabViewItems[selectedTabViewItemIndex].viewController else {
            return
        }

        var size = controller.preferredContentSize
        if let page = controller as? SettingsPageController, page.contentHeight > 0 {
            size = NSSize(width: SettingsLayout.pageWidth, height: page.contentHeight)
        }
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
