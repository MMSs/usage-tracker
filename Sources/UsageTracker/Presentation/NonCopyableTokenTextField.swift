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
        textContainerInset = Self.inset
        font = Self.defaultFont
        wantsLayer = true
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 5
    }

    required init?(coder: NSCoder) {
        nil
    }

    private static let inset = NSSize(width: 6, height: 4)
    private static let defaultFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)

    /// How tall the view must be to show `mask`'s document whole; 0 when it
    /// has none.
    static func height(fitting mask: CredentialMask?) -> CGFloat {
        guard let document = mask?.document else { return 0 }

        let lines = CGFloat(document.split(separator: "\n", omittingEmptySubsequences: false).count)
        return (lines * NSLayoutManager().defaultLineHeight(for: defaultFont)).rounded(.up) + 2 * inset.height
    }

    /// Wraps and lifts the one-line limit for long values such as a pasted JSON file.
    var allowsMultipleLines = false {
        didSet {
            textContainer?.maximumNumberOfLines = allowsMultipleLines ? 0 : 1
            textContainer?.lineBreakMode = allowsMultipleLines ? .byCharWrapping : .byTruncatingTail
            isVerticallyResizable = allowsMultipleLines
        }
    }

    /// Drawn in the placeholder color while the view is empty, with enough
    /// ellipses to fill the width, so a saved value reads as present.
    var placeholderMask: CredentialMask? {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard string.isEmpty, let placeholderMask else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? .systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.placeholderTextColor,
        ]
        let padding = textContainer?.lineFragmentPadding ?? 0

        if let document = placeholderMask.document {
            (document as NSString).draw(
                in: bounds.insetBy(dx: textContainerInset.width + padding, dy: textContainerInset.height),
                withAttributes: attributes
            )
            return
        }

        let fixedWidth = ((placeholderMask.prefix + placeholderMask.suffix) as NSString).size(withAttributes: attributes).width
        let ellipsisWidth = (CredentialMask.ellipsis as NSString).size(withAttributes: attributes).width
        let available = bounds.width - 2 * (textContainerInset.width + padding) - fixedWidth
        let text = placeholderMask.text(
            ellipsisCount: CredentialMask.ellipsisCount(availableWidth: available, ellipsisWidth: ellipsisWidth)
        )

        (text as NSString).draw(
            at: NSPoint(x: textContainerInset.width + padding, y: textContainerInset.height),
            withAttributes: attributes
        )
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
    var placeholderMask: CredentialMask?
    var focusesOnAppear = false
    var allowsMultipleLines = false
    var height: CGFloat = 26

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    /// The single-line view is returned bare so it fills its frame; the multi-line one
    /// sits in a scroll view and is at least `height` tall so a click anywhere focuses it.
    static func makeContainer(
        allowsMultipleLines: Bool,
        height: CGFloat,
        delegate: NSTextViewDelegate?
    ) -> NSView {
        let textView = NonCopyableTokenTextView()
        textView.delegate = delegate
        textView.allowsMultipleLines = allowsMultipleLines

        guard allowsMultipleLines else {
            return textView
        }

        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.frame = NSRect(x: 0, y: 0, width: 0, height: height)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        return scrollView
    }

    static func textView(in container: NSView) -> NSTextView? {
        (container as? NSScrollView)?.documentView as? NSTextView ?? container as? NSTextView
    }

    func makeNSView(context: Context) -> NSView {
        let container = Self.makeContainer(
            allowsMultipleLines: allowsMultipleLines,
            height: height,
            delegate: context.coordinator
        )

        (Self.textView(in: container) as? NonCopyableTokenTextView)?.placeholderMask = placeholderMask

        if focusesOnAppear, let textView = Self.textView(in: container) {
            // The view joins its window after this returns.
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }

        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard let textView = Self.textView(in: container) else {
            return
        }

        (textView as? NonCopyableTokenTextView)?.placeholderMask = placeholderMask

        if allowsMultipleLines, textView.minSize.height != height {
            textView.minSize = NSSize(width: 0, height: height)
            textView.setFrameSize(NSSize(width: textView.frame.width, height: max(textView.frame.height, height)))
        }

        guard textView.string != text else {
            return
        }

        textView.string = text

        if text.isEmpty {
            // A cleared secret must not come back through undo/redo.
            textView.undoManager?.removeAllActions()
        }
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
