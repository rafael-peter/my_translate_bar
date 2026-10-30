import AppKit
import SwiftUI

extension Notification.Name {
    static let translateBarReplaceEditor = Notification.Name("TranslateBar.replaceEditor")
}

/// A small AppKit bridge for the input field in the menu-bar popover.
///
/// The text view grows with its content between 65 and 200 points. Above the
/// limit the same view becomes scrollable, so a long paste never makes the
/// popover grow without bound. `onPaste` is called after AppKit has inserted
/// the pasteboard text and receives the complete current value through the
/// binding.
struct GrowingTextEditor: View {
    @Binding var text: String
    let focusRequestID: Int
    let replacementOwnerID: UUID
    /// Monotonic token for replacements initiated outside the text view (for
    /// example, the global import shortcut). Delayed AppKit paste callbacks
    /// carrying an older token are discarded by the coordinator.
    let replacementID: Int
    var onPaste: (String) -> Void

    init(
        text: Binding<String>,
        focusRequestID: Int = 0,
        replacementID: Int = 0,
        replacementOwnerID: UUID = UUID(),
        onPaste: @escaping (String) -> Void = { _ in }
    ) {
        _text = text
        self.focusRequestID = focusRequestID
        self.replacementID = replacementID
        self.replacementOwnerID = replacementOwnerID
        self.onPaste = onPaste
    }

    var body: some View {
        GrowingTextEditorRepresentable(
            text: $text,
            focusRequestID: focusRequestID,
            replacementID: replacementID,
            replacementOwnerID: replacementOwnerID,
            onPaste: onPaste
        )
        .clipped()
    }
}

private struct GrowingTextEditorRepresentable: NSViewRepresentable {
    @Binding var text: String
    let focusRequestID: Int
    let replacementID: Int
    let replacementOwnerID: UUID
    var onPaste: (String) -> Void

    private let minimumHeight: CGFloat = 65
    private let maximumHeight: CGFloat = 200

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = EditorScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.contentView.postsBoundsChangedNotifications = true

        let textView = PasteAwareTextView()
        textView.delegate = context.coordinator
        textView.onPaste = { [weak coordinator = context.coordinator, weak textView] epoch in
            guard let textView else { return }
            coordinator?.pasteDidFinish(textView, epoch: epoch)
        }
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = .systemFont(ofSize: 15)
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        // The document must be allowed to grow beyond the viewport. The
        // scroll view, whose SwiftUI size is capped at 200 pt, owns the
        // visible limit for long pastes.
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: minimumHeight)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.string = text

        scrollView.documentView = textView
        context.coordinator.lastFocusRequestID = nil
        context.coordinator.lastReplacementID = replacementID
        context.coordinator.replacementOwnerID = replacementOwnerID
        context.coordinator.observeReplacement(for: textView)
        scrollView.scheduleDocumentLayout()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PasteAwareTextView else { return }
        context.coordinator.parent = self
        context.coordinator.replacementOwnerID = replacementOwnerID
        textView.onPaste = { [weak coordinator = context.coordinator, weak textView] epoch in
            guard let textView else { return }
            coordinator?.pasteDidFinish(textView, epoch: epoch)
        }

        if context.coordinator.lastReplacementID != replacementID {
            // Invalidate callbacks already queued by NSTextView before the
            // outside replacement reached the binding.
            textView.replacementEpoch &+= 1
            context.coordinator.lastReplacementID = replacementID
        }

        if textView.string != text && !textView.hasMarkedText() {
            let selectedRange = textView.selectedRange()
            textView.string = text
            let safeLocation = min(selectedRange.location, textView.string.utf16.count)
            textView.setSelectedRange(NSRange(location: safeLocation, length: 0))
        }
        (scrollView as? EditorScrollView)?.scheduleDocumentLayout()

        guard context.coordinator.lastFocusRequestID != focusRequestID else { return }
        context.coordinator.lastFocusRequestID = focusRequestID
        DispatchQueue.main.async { [weak textView] in
            guard let textView, let window = textView.window else { return }
            window.makeFirstResponder(textView)
        }
    }

    // The requirement returns `CGSize?`; a non-optional overload is never
    // called and SwiftUI collapses the scroll view to zero height.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        guard let textView = nsView.documentView as? NSTextView else {
            return CGSize(width: proposal.width ?? 320, height: minimumHeight)
        }

        let proposedWidth = proposal.width ?? 320
        let width = proposedWidth.isFinite ? max(1, proposedWidth) : 320
        let height = EditorTextMeasurement.documentHeight(for: textView, width: width)
        return CGSize(width: width, height: min(max(height, minimumHeight), maximumHeight))
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: GrowingTextEditorRepresentable
        var lastFocusRequestID: Int?
        var lastReplacementID: Int?
        var replacementOwnerID: UUID?

        init(_ parent: GrowingTextEditorRepresentable) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, !textView.hasMarkedText() else { return }
            guard textView.string != parent.text else { return }
            parent.text = textView.string
            if let scrollView = textView.enclosingScrollView {
                (scrollView as? EditorScrollView)?.scheduleDocumentLayout()
            }
        }

        func pasteDidFinish(_ textView: PasteAwareTextView, epoch: UInt64) {
            // `super.paste` has synchronously inserted plain text. Handling
            // this in the same turn avoids a stale callback racing an outside
            // replacement before SwiftUI can propagate its new token.
            guard textView.acceptsPaste(epoch: epoch) else { return }
            if textView.string != parent.text {
                parent.text = textView.string
            }
            parent.onPaste(textView.string)
        }

        func observeReplacement(for textView: PasteAwareTextView) {
            replacementTarget = textView
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(replacementNotification(_:)),
                name: .translateBarReplaceEditor,
                object: nil
            )
        }

        private weak var replacementTarget: PasteAwareTextView?

        @objc nonisolated private func replacementNotification(_ notification: Notification) {
            guard let userInfo = notification.userInfo,
                  let ownerID = userInfo["owner"] as? UUID,
                  let replacementID = userInfo["id"] as? Int,
                  let replacementText = userInfo["text"] as? String else { return }
            MainActor.assumeIsolated {
                guard ownerID == self.replacementOwnerID,
                      let textView = self.replacementTarget else { return }
                self.applyExternalReplacement(replacementText, id: replacementID, to: textView)
            }
        }

        private func applyExternalReplacement(_ text: String, id: Int, to textView: PasteAwareTextView) {
            guard id != lastReplacementID else { return }
            lastReplacementID = id
            textView.replaceDocument(with: text)
        }

    }
}

/// Measure a detached text layout: SwiftUI can propose several widths in one
/// pass, so measuring must never resize the live editor or its text container.
@MainActor
enum EditorTextMeasurement {
    static func documentHeight(for textView: NSTextView, width: CGFloat) -> CGFloat {
        let storage = NSTextStorage(attributedString: textView.attributedString())
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(
            width: max(1, width - textView.textContainerInset.width * 2),
            height: .greatestFiniteMagnitude
        ))
        container.lineFragmentPadding = textView.textContainer?.lineFragmentPadding ?? 0
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        manager.ensureLayout(for: container)
        let textHeight = max(manager.usedRect(for: container).maxY, manager.extraLineFragmentRect.maxY)
        return max(65, ceil(textHeight + textView.textContainerInset.height * 2))
    }
}

private final class EditorScrollView: NSScrollView {
    private var documentLayoutScheduled = false

    override func layout() {
        super.layout()
        scheduleDocumentLayout()
    }

    func scheduleDocumentLayout() {
        guard !documentLayoutScheduled else { return }
        documentLayoutScheduled = true
        // Resize only after AppKit/SwiftUI have finished their current layout.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.documentLayoutScheduled = false
            guard let editor = self.documentView as? NSTextView,
                  self.contentSize.width > 0 else { return }
            let size = NSSize(
                width: self.contentSize.width,
                height: EditorTextMeasurement.documentHeight(for: editor, width: self.contentSize.width)
            )
            if editor.frame.size != size {
                editor.setFrameSize(size)
            }
        }
    }
}

final class PasteAwareTextView: NSTextView {
    var onPaste: ((UInt64) -> Void)?
    var replacementEpoch: UInt64 = 0

    func replaceDocument(with text: String) {
        replacementEpoch &+= 1
        unmarkText()
        string = text
        undoManager?.removeAllActions()
        let end = string.utf16.count
        setSelectedRange(NSRange(location: end, length: 0))
        scrollRangeToVisible(NSRange(location: end, length: 0))
    }

    func acceptsPaste(epoch: UInt64) -> Bool {
        epoch == replacementEpoch
    }

    override func paste(_ sender: Any?) {
        guard NSPasteboard.general.string(forType: .string) != nil else {
            super.paste(sender)
            return
        }
        let epoch = replacementEpoch
        super.paste(sender)
        onPaste?(epoch)
    }
}
