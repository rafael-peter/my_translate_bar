import AppKit
import SwiftUI
import XCTest
@testable import TranslateBar

@MainActor
final class GrowingTextEditorTests: XCTestCase {
    func testExternalReplacementInvalidatesQueuedPasteAndResetsCaret() {
        let editor = PasteAwareTextView(frame: .zero)
        editor.string = "texto antigo"
        let queuedPasteEpoch = editor.replacementEpoch

        editor.replaceDocument(with: "texto novo")

        XCTAssertEqual(editor.string, "texto novo")
        XCTAssertFalse(editor.acceptsPaste(epoch: queuedPasteEpoch))
        XCTAssertEqual(editor.selectedRange().location, editor.string.utf16.count)
        XCTAssertTrue(editor.acceptsPaste(epoch: editor.replacementEpoch))
    }

    func testRepeatedExternalReplacementsDiscardEachPreviousEpoch() {
        let editor = PasteAwareTextView(frame: .zero)
        editor.replaceDocument(with: "primeiro")
        let firstEpoch = editor.replacementEpoch

        editor.replaceDocument(with: "segundo")
        let secondEpoch = editor.replacementEpoch
        editor.replaceDocument(with: "terceiro")

        XCTAssertEqual(editor.string, "terceiro")
        XCTAssertFalse(editor.acceptsPaste(epoch: firstEpoch))
        XCTAssertFalse(editor.acceptsPaste(epoch: secondEpoch))
        XCTAssertTrue(editor.acceptsPaste(epoch: editor.replacementEpoch))
    }

    func testModelReplacementSynchronouslyUpdatesHostedEditorAndRejectsOldCallback() {
        let model = makeModel()
        model.sourceText = "texto antigo"
        var callbackCount = 0
        let binding = Binding<String>(
            get: { model.sourceText },
            set: { model.sourceText = $0 }
        )
        let hosted = NSHostingView(
            rootView: GrowingTextEditor(
                text: binding,
                replacementID: model.editorReplacementID,
                replacementOwnerID: model.editorReplacementOwnerID
            ) { _ in
                callbackCount += 1
            }
        )
        hosted.frame = NSRect(x: 0, y: 0, width: 320, height: 65)
        hosted.layoutSubtreeIfNeeded()
        guard let editor = findEditor(in: hosted) else {
            return XCTFail("The hosted editor was not created")
        }
        let oldEpoch = editor.replacementEpoch

        model.replaceTextFromShortcut("texto novo")

        XCTAssertEqual(editor.string, "texto novo")
        XCTAssertEqual(model.sourceText, "texto novo")
        editor.onPaste?(oldEpoch)
        XCTAssertEqual(callbackCount, 0)

        let otherModel = makeModel()
        otherModel.replaceTextFromShortcut("outro modelo")
        XCTAssertEqual(editor.string, "texto novo")
    }

    private func findEditor(in view: NSView) -> PasteAwareTextView? {
        if let editor = view as? PasteAwareTextView { return editor }
        for child in view.subviews {
            if let editor = findEditor(in: child) { return editor }
        }
        return nil
    }

    private func makeModel() -> AppModel {
        let suiteName = "TranslateBarTests.Editor.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return AppModel(history: HistoryStore(defaults: defaults), defaults: defaults)
    }
}
