import AppKit
import Testing
@testable import UsageTracker

/// Its own class, so the animator's hooks touch no other test's windows.
private final class AnimatedTestPanel: NSPanel {}

@MainActor
struct PopoverWindowAnimatorTests {
    private func makePanel() -> NSPanel {
        let panel = AnimatedTestPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        return panel
    }

    /// Lets the fades finish.
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(400))
    }

    /// Clicking from one item straight to another closes the first panel while
    /// the second opens, which must not leave the first one up but invisible.
    @Test func openingAnotherPanelWhileOneClosesStillClosesIt() async throws {
        let first = makePanel()
        let second = makePanel()
        defer {
            first.orderOut(nil)
            second.orderOut(nil)
        }
        PopoverWindowAnimator.install(on: first)
        first.makeKeyAndOrderFront(nil)
        try await settle()

        first.orderOut(nil)
        second.makeKeyAndOrderFront(nil)
        try await settle()

        #expect(!first.isVisible)
        #expect(second.isVisible)
        #expect(second.alphaValue == 1)

        first.makeKeyAndOrderFront(nil)
        try await settle()

        #expect(first.isVisible)
        #expect(first.alphaValue == 1)
    }

    @Test func reopeningAPanelWhileItClosesKeepsItUp() async throws {
        let panel = makePanel()
        defer { panel.orderOut(nil) }
        PopoverWindowAnimator.install(on: panel)
        panel.makeKeyAndOrderFront(nil)
        try await settle()

        panel.orderOut(nil)
        panel.makeKeyAndOrderFront(nil)
        try await settle()

        #expect(panel.isVisible)
        #expect(panel.alphaValue == 1)
        #expect(!panel.ignoresMouseEvents)
    }
}
