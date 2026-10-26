import AppKit
import Testing
@testable import UsageTracker

/// Its own class, so the animator's hooks touch no other test's windows.
private final class AnimatedTestPanel: NSPanel {}

@MainActor
@Suite(.serialized)
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

    /// Polls `condition` in 10 ms steps, yielding to the main run loop so the
    /// fades' completion handlers can run, until it holds or `timeout` passes.
    /// Returns whether it held, so a state that never arrives fails the
    /// `#expect` that names it instead of hanging.
    private func wait(
        until condition: @MainActor () -> Bool,
        timeout: Duration = .seconds(2)
    ) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now >= deadline { return false }
            try await Task.sleep(for: .milliseconds(10))
        }
        return true
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
        let firstOpened = try await wait { first.isVisible && first.alphaValue == 1 }
        #expect(firstOpened, "first panel never finished opening")

        first.orderOut(nil)
        second.makeKeyAndOrderFront(nil)
        let swapped = try await wait {
            !first.isVisible && second.isVisible && second.alphaValue == 1
        }
        #expect(swapped, "first is ordered out, second is fully opaque")
        #expect(!first.isVisible)
        #expect(second.isVisible)
        #expect(second.alphaValue == 1)

        first.makeKeyAndOrderFront(nil)
        let firstReopened = try await wait { first.isVisible && first.alphaValue == 1 }
        #expect(firstReopened, "first is visible and fully opaque again")
        #expect(first.isVisible)
        #expect(first.alphaValue == 1)
    }

    @Test func reopeningAPanelWhileItClosesKeepsItUp() async throws {
        let panel = makePanel()
        defer { panel.orderOut(nil) }
        PopoverWindowAnimator.install(on: panel)
        panel.makeKeyAndOrderFront(nil)
        let opened = try await wait { panel.isVisible && panel.alphaValue == 1 }
        #expect(opened, "panel never finished opening")

        panel.orderOut(nil)
        panel.makeKeyAndOrderFront(nil)
        let reopened = try await wait { panel.isVisible && panel.alphaValue == 1 }
        #expect(reopened, "panel is visible and fully opaque after the reopen")
        #expect(panel.isVisible)
        #expect(panel.alphaValue == 1)
        #expect(!panel.ignoresMouseEvents)
    }
}
