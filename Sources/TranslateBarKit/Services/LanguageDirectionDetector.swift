import Foundation
import NaturalLanguage

/// Detects only the two directions offered by the app. Short or ambiguous
/// text returns nil so typing a few characters cannot unexpectedly flip the UI.
struct LanguageDirectionDetector: Sendable {
    private let minimumCharacters = 4

    func language(for text: String) -> TranslationLanguage? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= minimumCharacters else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(value)
        guard let language = recognizer.dominantLanguage,
              let probability = recognizer.languageHypotheses(withMaximum: 2)[language],
              probability >= 0.72 else { return nil }

        switch language {
        case .english: return .english
        case .portuguese: return .portugueseBrazil
        default: return nil
        }
    }
}
