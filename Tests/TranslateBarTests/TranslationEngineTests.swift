import XCTest
@testable import TranslateBar

final class TranslationEngineTests: XCTestCase {
    func testDictionaryIsDirectionalAndAccentsArePreserved() async throws {
        let engine = TranslationEngine(dictionary: OfflineDictionary())

        let english = try await engine.translate(.init(text: "não", source: .portugueseBrazil, target: .english))
        XCTAssertEqual(english.text, "no")
        XCTAssertEqual(english.origin, .dictionary)

        let portuguese = try await engine.translate(.init(text: "hello", source: .english, target: .portugueseBrazil))
        XCTAssertEqual(portuguese.text, "olá")

        do {
            _ = try await engine.translate(.init(text: "hello", source: .portugueseBrazil, target: .english))
            XCTFail("A word must not be accepted in the opposite direction.")
        } catch TranslationEngineError.systemTranslationRequired {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAccentedAndUnaccentedKeysDoNotCollide() async throws {
        let dictionary = OfflineDictionary(directionalEntries: [
            .portugueseBrazil: [
                .english: ["não": ["no"], "nao": ["not accented"]]
            ]
        ])
        let engine = TranslationEngine(dictionary: dictionary)

        let accented = try await engine.translate(.init(text: "não", source: .portugueseBrazil, target: .english))
        let plain = try await engine.translate(.init(text: "nao", source: .portugueseBrazil, target: .english))
        XCTAssertEqual(accented.text, "no")
        XCTAssertEqual(plain.text, "not accented")
    }

    func testBundledFreeDictKeepsAlternativeSenses() {
        let dictionary = OfflineDictionary.bundled()
        let alternatives = dictionary.lookupAlternatives("hello", source: .english, target: .portugueseBrazil)
        XCTAssertEqual(alternatives?.first, "alô")
        XCTAssertTrue((alternatives?.count ?? 0) >= 2)
    }

    func testCachePreservesExactInputAndReportsCacheOrigin() async throws {
        let engine = TranslationEngine(dictionary: OfflineDictionary())
        let request = TranslationRequest(text: "hello", source: .english, target: .portugueseBrazil)

        let first = try await engine.translate(request)
        let second = try await engine.translate(request)
        XCTAssertEqual(first.origin, .dictionary)
        XCTAssertEqual(second.origin, .cache)

        do {
            _ = try await engine.translate(.init(text: "hello!", source: .english, target: .portugueseBrazil))
            XCTFail("Punctuation changes the exact cache key and requires contextual translation.")
        } catch TranslationEngineError.systemTranslationRequired {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUnknownSentenceRequiresContextualProvider() async {
        let engine = TranslationEngine(dictionary: OfflineDictionary())
        do {
            _ = try await engine.translate(.init(text: "The quick brown fox jumps.", source: .english, target: .portugueseBrazil))
            XCTFail("An unknown sentence must be sent to contextual translation.")
        } catch TranslationEngineError.systemTranslationRequired {
            // Expected: a word list cannot safely translate grammar.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCacheIsBounded() async throws {
        var entries: [String: [String]] = [:]
        for index in 0..<300 {
            entries["token\(index)"] = ["valor\(index)"]
        }
        let dictionary = OfflineDictionary(directionalEntries: [
            .english: [.portugueseBrazil: entries]
        ])
        let engine = TranslationEngine(dictionary: dictionary)
        for index in 0..<300 {
            _ = try await engine.translate(.init(text: "token\(index)", source: .english, target: .portugueseBrazil))
        }
        let cacheCount = await engine.cacheCount
        XCTAssertLessThanOrEqual(cacheCount, 256)
    }
}
