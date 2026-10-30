import AppKit
import SwiftUI
import Testing
@testable import TranslateBarKit

@MainActor
struct EditorLayoutTests {
    @Test func measuringProposalsDoesNotMutateTheLiveEditor() {
        let editor = PasteAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 65))
        editor.font = .systemFont(ofSize: 15)
        editor.textContainerInset = NSSize(width: 6, height: 8)
        editor.string = String(repeating: "Texto para medir sem alterar o editor. ", count: 30)
        let frame = editor.frame
        let containerSize = editor.textContainer?.containerSize
        let selection = editor.selectedRange()

        let narrow = EditorTextMeasurement.documentHeight(for: editor, width: 150)
        let wide = EditorTextMeasurement.documentHeight(for: editor, width: 320)
        let repeated = EditorTextMeasurement.documentHeight(for: editor, width: 150)

        #expect(narrow > wide)
        #expect(wide > 200)
        #expect(narrow == repeated)
        #expect(editor.frame == frame)
        #expect(editor.textContainer?.containerSize == containerSize)
        #expect(editor.selectedRange() == selection)
    }

    @Test func emptyAndShortDocumentsKeepMinimumHeight() {
        let editor = PasteAwareTextView()
        editor.font = .systemFont(ofSize: 15)
        editor.textContainerInset = NSSize(width: 6, height: 8)
        #expect(EditorTextMeasurement.documentHeight(for: editor, width: 320) == 65)
        editor.string = "Olá"
        #expect(EditorTextMeasurement.documentHeight(for: editor, width: 320) == 65)
    }

    @Test func trailingNewlineIncludesTheCaretLine() {
        let editor = PasteAwareTextView()
        editor.font = .systemFont(ofSize: 15)
        editor.string = String(repeating: "linha\n", count: 10) + "fim"
        let before = EditorTextMeasurement.documentHeight(for: editor, width: 320)
        editor.string += "\n"
        #expect(EditorTextMeasurement.documentHeight(for: editor, width: 320) > before)
    }

    @Test func hostedEditorReportsItsHeightToSwiftUI() {
        func fittingHeight(_ text: String) -> CGFloat {
            NSHostingView(rootView: GrowingTextEditor(text: .constant(text)).frame(width: 320)).fittingSize.height
        }
        #expect(fittingHeight("") == 65)
        #expect(fittingHeight(String(repeating: "linha\n", count: 6)) > 65)
        #expect(fittingHeight(String(repeating: "linha\n", count: 40)) == 200)
    }
}
