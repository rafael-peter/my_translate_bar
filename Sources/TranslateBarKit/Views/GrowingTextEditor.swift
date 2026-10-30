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
    @State private var measuredHeight: CGFloat = 65

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
            onPaste: onPaste,
            measuredHeight: $measuredHeight
        )
        .frame(height: min(max(measuredHeight, 65), 200))
        .clipped()
    }
}

private struct GrowingTextEditorRepresentable: NSViewRepresentable {
    @Binding var text: String
    let focusRequestID: Int
    let replacementID: Int
    let replacementOwnerID: UUID
    var onPaste: (String) -> Void
    @Binding var measuredHeight: CGFloat

    private let minimumHeight: CGFloat = 65
    private let maximumHeight: CGFloat = 200

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
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
        context.coordinator.updateScrollState(for: textView, in: scrollView)
        context.coordinator.reportHeight(for: textView, in: scrollView)
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
        context.coordinator.updateScrollState(for: textView, in: scrollView)
        context.coordinator.reportHeight(for: textView, in: scrollView)

        guard context.coordinator.lastFocusRequestID != focusRequestID else { return }
        context.coordinator.lastFocusRequestID = focusRequestID
        DispatchQueue.main.async { [weak textView] in
            guard let textView, let window = textView.window else { return }
            window.makeFirstResponder(textView)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize {
        guard let textView = nsView.documentView as? NSTextView else {
            return CGSize(width: proposal.width ?? 320, height: minimumHeight)
        }

        let width = max(1, proposal.width ?? 320)
        let contentWidth = max(1, width - textView.textContainerInset.width * 2)
        textView.textContainer?.containerSize = NSSize(width: contentWidth, height: .greatestFiniteMagnitude)
        guard let container = textView.textContainer, let layoutManager = textView.layoutManager else {
            return CGSize(width: width, height: minimumHeight)
        }
        layoutManager.ensureLayout(for: container)
        let documentHeight = max(
            layoutManager.usedRect(for: container).height + textView.textContainerInset.height * 2,
            minimumHeight
        )
        textView.frame = NSRect(x: 0, y: 0, width: width, height: ceil(documentHeight))
        let height = min(documentHeight, maximumHeight)
        reportHeight(height)
        return CGSize(width: width, height: ceil(height))
    }

    private func reportHeight(_ height: CGFloat) {
        let clamped = min(max(ceil(height), minimumHeight), maximumHeight)
        guard abs(measuredHeight - clamped) > 0.5 else { return }
        DispatchQueue.main.async {
            if abs(self.measuredHeight - clamped) > 0.5 {
                self.measuredHeight = clamped
            }
        }
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
                updateScrollState(for: textView, in: scrollView)
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

        func updateScrollState(for textView: NSTextView, in scrollView: NSScrollView) {
            let contentHeight = measuredHeight(for: textView)
            let shouldScroll = contentHeight > 200
            scrollView.hasVerticalScroller = shouldScroll
            scrollView.verticalScrollElasticity = .allowed
            // Keep the document resizable even while it is shorter than the
            // viewport. Turning this off for short text makes a later long
            // paste retain a stale document frame and prevents scrolling.
            textView.isVerticallyResizable = true
            textView.frame.size.height = max(contentHeight, 1)
        }

        func reportHeight(for textView: NSTextView, in scrollView: NSScrollView) {
            let contentHeight = measuredHeight(for: textView)
            let clamped = min(max(ceil(contentHeight), 65), 200)
            DispatchQueue.main.async { [weak self] in
                guard let self, abs(self.parent.measuredHeight - clamped) > 0.5 else { return }
                self.parent.measuredHeight = clamped
            }
        }

        private func measuredHeight(for textView: NSTextView) -> CGFloat {
            guard let container = textView.textContainer, let layoutManager = textView.layoutManager else { return 65 }
            let width = max(1, textView.bounds.width - textView.textContainerInset.width * 2)
            container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
            layoutManager.ensureLayout(for: container)
            return layoutManager.usedRect(for: container).height + textView.textContainerInset.height * 2
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
