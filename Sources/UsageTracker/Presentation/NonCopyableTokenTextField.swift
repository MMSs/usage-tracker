import AppKit
import SwiftUI

final class NonCopyableTokenTextView: NSTextView {
    override init(frame frameRect: NSRect = .zero, textContainer container: NSTextContainer? = nil) {
        let textContainer = container ?? NSTextContainer()
        let layoutManager = NSLayoutManager()
        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        textContainer.widthTracksTextView = true
        textContainer.maximumNumberOfLines = 1
        textContainer.lineBreakMode = .byTruncatingTail

        super.init(frame: frameRect, textContainer: textContainer)
        isEditable = true
        isSelectable = true
        isRichText = false
        allowsUndo = true
        drawsBackground = true
        backgroundColor = .textBackgroundColor
        textContainerInset = NSSize(width: 6, height: 4)
        font = .systemFont(ofSize: NSFont.systemFontSize)
        wantsLayer = true
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 5
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// Wraps and lifts the one-line limit for long values such as a pasted JSON file.
    var allowsMultipleLines = false {
        didSet {
            textContainer?.maximumNumberOfLines = allowsMultipleLines ? 0 : 1
            textContainer?.lineBreakMode = allowsMultipleLines ? .byCharWrapping : .byTruncatingTail
            isVerticallyResizable = allowsMultipleLines
        }
    }

    override func copy(_ sender: Any?) {}

    override func cut(_ sender: Any?) {}

    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] {
        []
    }

    override func writeSelection(to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        false
    }

    override func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        []
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(copy(_:)), #selector(cut(_:)):
            return false
        default:
            return super.validateUserInterfaceItem(item)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if modifiers == .command, ["c", "x"].contains(event.charactersIgnoringModifiers?.lowercased()) {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }
}

struct NonCopyableTokenTextField: NSViewRepresentable {
    @Binding var text: String
    var focusesOnAppear = false
    var allowsMultipleLines = false

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NonCopyableTokenTextView()
        textView.delegate = context.coordinator
        textView.allowsMultipleLines = allowsMultipleLines
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = allowsMultipleLines
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView

        if focusesOnAppear {
            // The view joins its window after this returns.
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else {
            return
        }

        textView.string = text
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }

            text = textView.string
        }
    }
}
