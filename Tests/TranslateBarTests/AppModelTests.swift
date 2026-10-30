import XCTest
@testable import TranslateBar

@MainActor
final class AppModelTests: XCTestCase {
    func testTypingSchedulesTranslationAfterDebounce() async {
        let model = makeModel()
        model.sourceText = "hello"
        XCTAssertFalse(model.isTranslating)

        try? await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertTrue(model.isTranslating || model.lastResult != nil)
    }

    func testPasteTextUsesDictionaryImmediately() async {
        let model = makeModel()
        model.pasteText("hello")

        try? await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(model.lastResult?.origin, .dictionary)
        XCTAssertEqual(model.translatedText, "alô")
        XCTAssertEqual(model.sourceText, "hello")
    }

    func testShortcutReplacementReplacesExistingEditorValue() async {
        let model = makeModel()
        model.sourceText = "texto antigo"

        model.replaceTextFromShortcut("new text")
        await Task.yield()

        XCTAssertEqual(model.sourceText, "new text")
    }

    func testClearingBeforeDebouncePreventsTranslation() async {
        let model = makeModel()
        model.sourceText = "hello"
        model.clear()

        try? await Task.sleep(nanoseconds: 450_000_000)

        XCTAssertNil(model.lastResult)
        XCTAssertFalse(model.isTranslating)
    }

    func testAutomaticDirectionFollowsNewTextButManualSwapIsPreserved() async {
        let model = makeModel()
        model.sourceLanguage = .portugueseBrazil
        model.targetLanguage = .english
        model.pasteText("This is an English sentence.")

        XCTAssertEqual(model.sourceLanguage, .english)
        XCTAssertEqual(model.targetLanguage, .portugueseBrazil)

        model.swapLanguages()
        XCTAssertEqual(model.sourceLanguage, .portugueseBrazil)
        XCTAssertEqual(model.targetLanguage, .english)
        model.sourceText = "This is a different English sentence."
        try? await Task.sleep(nanoseconds: 450_000_000)
        XCTAssertEqual(model.sourceLanguage, .english)
        XCTAssertEqual(model.targetLanguage, .portugueseBrazil)
    }

    func testLanguagePickersCannotSelectTheSameDirection() {
        let model = makeModel()
        model.targetLanguage = .english

        XCTAssertNotEqual(model.sourceLanguage, model.targetLanguage)
    }
    func testEditingSourceTextInvalidatesPendingTranslation() {
        let model = makeModel()
        model.sourceText = "hello"

        model.translate()
        XCTAssertTrue(model.isTranslating)

        model.sourceText = "good morning"

        XCTAssertFalse(model.isTranslating)
        XCTAssertNil(model.lastResult)
        XCTAssertNil(model.errorMessage)
    }

    func testChangingTargetLanguageInvalidatesPendingTranslation() {
        let model = makeModel()
        model.sourceText = "hello"

        model.translate()
        XCTAssertTrue(model.isTranslating)

        model.targetLanguage = .english

        XCTAssertFalse(model.isTranslating)
        XCTAssertNil(model.lastResult)
        XCTAssertNil(model.errorMessage)
    }

    func testClearCancelsPendingTranslationAndResetsEditor() {
        let model = makeModel()
        model.sourceText = "hello"
        model.translate()

        model.clear()

        XCTAssertEqual(model.sourceText, "")
        XCTAssertEqual(model.translatedText, "")
        XCTAssertFalse(model.isTranslating)
        XCTAssertNil(model.lastResult)
        XCTAssertNil(model.errorMessage)
    }

    private func makeModel(file: StaticString = #filePath, line: UInt = #line) -> AppModel {
        let suiteName = "TranslateBarTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create isolated UserDefaults", file: file, line: line)
            fatalError("Could not create isolated UserDefaults")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return AppModel(history: HistoryStore(defaults: defaults), defaults: defaults)
    }
}
