import AppKit
import SwiftUI

/// Hands back the window hosting a SwiftUI view once it has one.
struct HostingWindowReader: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        WindowObservingView(onWindow: onWindow)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowObservingView: NSView {
        let onWindow: (NSWindow) -> Void

        init(onWindow: @escaping (NSWindow) -> Void) {
            self.onWindow = onWindow
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow(window) }
        }
    }
}

enum PopoverLayout {
    /// Total width of every popover page, padding included.
    static let width: CGFloat = 300
}

/// Reference-typed so the event monitor closure and the view share one copy.
final class EscapeMonitorState {
    var monitor: Any?
    weak var window: NSWindow?
}

enum MenuBarPopover {
    /// Closes the popover the way the menu bar item does, so MenuBarExtra's
    /// open/closed state stays in sync. With several items in the bar, the
    /// open one is the highlighted button.
    @MainActor
    static func dismiss() {
        let buttons = NSApp.windows
            .filter { $0.className == "NSStatusBarWindow" && $0.isVisible }
            .compactMap { button(in: $0.contentView) }
        buttons.first { $0.isHighlighted }?.performClick(nil)
    }

    @MainActor
    private static func button(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }

        for subview in view.subviews {
            if let found = button(in: subview) { return found }
        }

        return nil
    }
}
