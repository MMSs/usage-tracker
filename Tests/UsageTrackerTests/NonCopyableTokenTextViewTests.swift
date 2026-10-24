import AppKit
import Testing
@testable import UsageTracker

@MainActor
struct NonCopyableTokenTextViewTests {
    @Test func tokenTextViewBlocksCopyAndCutWhilePreservingSelectionAndTextReplacement() {
        let textView = NonCopyableTokenTextView()
        textView.string = "session-token"
        textView.selectAll(nil)

        #expect(textView.selectedRange() == NSRange(location: 0, length: 13))

        textView.copy(nil)
        textView.cut(nil)

        #expect(textView.string == "session-token")
        #expect(!textView.validateUserInterfaceItem(NSMenuItem(
            title: "Copy",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )))
        #expect(!textView.validateUserInterfaceItem(NSMenuItem(
            title: "Cut",
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        )))
        #expect(textView.responds(to: #selector(NSText.paste(_:))))

        textView.insertText("replacement-token", replacementRange: textView.selectedRange())

        #expect(textView.string == "replacement-token")
    }

    @Test func tokenTextViewBlocksDragExportOfSelectedText() {
        let textView = NonCopyableTokenTextView()
        textView.string = "session-token"
        textView.selectAll(nil)

        let dragPasteboard = NSPasteboard(name: NSPasteboard.Name("NonCopyableTokenTextViewTests.drag"))

        #expect(textView.writablePasteboardTypes.isEmpty)
        #expect(textView.writeSelection(to: dragPasteboard, type: .string) == false)
        #expect(textView.writeSelection(to: dragPasteboard, types: [.string]) == false)
        #expect(textView.string == "session-token")
    }

    @Test func singleLineByDefaultAndMultipleLinesWhenAllowed() {
        let textView = NonCopyableTokenTextView()
        #expect(textView.textContainer?.maximumNumberOfLines == 1)

        textView.allowsMultipleLines = true

        #expect(textView.textContainer?.maximumNumberOfLines == 0)
        #expect(textView.textContainer?.lineBreakMode == .byCharWrapping)
    }
}
