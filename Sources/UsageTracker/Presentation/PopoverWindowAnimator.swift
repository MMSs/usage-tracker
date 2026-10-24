import AppKit
import ObjectiveC
import QuartzCore

/// Fades the menu bar popover in on open and out on close. The popover window
/// belongs to `MenuBarExtra`, which offers no animation hooks, so this
/// intercepts the window's own show and hide calls. Fading the window rather
/// than a layer takes its shadow and border along with it.
@MainActor
enum PopoverWindowAnimator {
    private static let fadeDuration: TimeInterval = 0.1

    private static var hookedClasses: Set<ObjectIdentifier> = []
    private static var closeGeneration = 0
    private static var isClosing = false

    static func install(on window: NSWindow) {
        guard let windowClass = hookableClass(of: window),
              hookedClasses.insert(ObjectIdentifier(windowClass)).inserted else {
            return
        }

        hookOrderOut(on: windowClass)
        hookMakeKeyAndOrderFront(on: windowClass)

        // The first open starts before the hooks are in place.
        if !reduceMotion { window.alphaValue = 0 }
        playOpen(window)
    }

    /// Runtime KVO subclasses come and go, so hook the class SwiftUI defined.
    private static func hookableClass(of window: NSWindow) -> AnyClass? {
        var windowClass: AnyClass? = object_getClass(window)
        while let current = windowClass, NSStringFromClass(current).hasPrefix("NSKVONotifying_") {
            windowClass = class_getSuperclass(current)
        }

        return windowClass
    }

    private static func hookOrderOut(on windowClass: AnyClass) {
        typealias OrderOut = @convention(c) (NSWindow, Selector, AnyObject?) -> Void
        let selector = #selector(NSWindow.orderOut(_:))
        guard let method = class_getInstanceMethod(windowClass, selector) else { return }

        let original = unsafeBitCast(method_getImplementation(method), to: OrderOut.self)
        let replacement: @convention(block) (NSWindow, AnyObject?) -> Void = { window, sender in
            MainActor.assumeIsolated {
                playClose(window) { original(window, selector, sender) }
            }
        }
        replace(selector, in: windowClass, types: method_getTypeEncoding(method), with: imp_implementationWithBlock(replacement))
    }

    private static func hookMakeKeyAndOrderFront(on windowClass: AnyClass) {
        typealias OrderFront = @convention(c) (NSWindow, Selector, AnyObject?) -> Void
        let selector = #selector(NSWindow.makeKeyAndOrderFront(_:))
        guard let method = class_getInstanceMethod(windowClass, selector) else { return }

        let original = unsafeBitCast(method_getImplementation(method), to: OrderFront.self)
        let replacement: @convention(block) (NSWindow, AnyObject?) -> Void = { window, sender in
            MainActor.assumeIsolated {
                let wasVisible = window.isVisible && !isClosing
                cancelClose(window)
                // Transparent before it reaches the screen, so the first frame
                // never flashes at full opacity.
                if !window.isVisible, !reduceMotion { window.alphaValue = 0 }
                original(window, selector, sender)
                if !wasVisible { playOpen(window) }
            }
        }
        replace(selector, in: windowClass, types: method_getTypeEncoding(method), with: imp_implementationWithBlock(replacement))
    }

    /// Overrides the method on this class only, whether it defines it or inherits it.
    private static func replace(_ selector: Selector, in windowClass: AnyClass, types: UnsafePointer<CChar>?, with implementation: IMP) {
        if !class_addMethod(windowClass, selector, implementation, types),
           let own = class_getInstanceMethod(windowClass, selector) {
            method_setImplementation(own, implementation)
        }
    }

    private static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private static func playOpen(_ window: NSWindow) {
        guard !reduceMotion else {
            window.alphaValue = 1
            return
        }

        fade(window, to: 1)
    }

    private static func playClose(_ window: NSWindow, orderOut: @escaping () -> Void) {
        guard !reduceMotion, !isClosing, window.isVisible else {
            if !isClosing { orderOut() }
            return
        }

        isClosing = true
        closeGeneration += 1
        let generation = closeGeneration
        window.ignoresMouseEvents = true

        fade(window, to: 0) {
            guard generation == closeGeneration, isClosing else { return }
            isClosing = false
            orderOut()
            reset(window)
        }
    }

    /// A reopen during the close animation keeps the window up instead.
    private static func cancelClose(_ window: NSWindow) {
        guard isClosing else { return }

        isClosing = false
        closeGeneration += 1
        window.ignoresMouseEvents = false
    }

    private static func reset(_ window: NSWindow) {
        window.alphaValue = 1
        window.ignoresMouseEvents = false
    }

    private static func fade(_ window: NSWindow, to alpha: CGFloat, completion: (@MainActor () -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: alpha > 0 ? .easeOut : .easeIn)
            window.animator().alphaValue = alpha
        } completionHandler: {
            MainActor.assumeIsolated { completion?() }
        }
    }
}
