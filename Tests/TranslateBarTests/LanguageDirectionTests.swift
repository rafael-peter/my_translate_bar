import XCTest
@testable import TranslateBar

final class LanguageDirectionTests: XCTestCase {
    func testDetectsEnglishAndPortugueseSentences() {
        let detector = LanguageDirectionDetector()
        XCTAssertEqual(detector.language(for: "This is a sentence written in English."), .english)
        XCTAssertEqual(detector.language(for: "Esta é uma frase escrita em português."), .portugueseBrazil)
    }

    func testRejectsAmbiguousShortInput() {
        XCTAssertNil(LanguageDirectionDetector().language(for: "hi"))
    }
}
