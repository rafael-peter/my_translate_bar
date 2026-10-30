import Foundation

enum TranslationLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case english = "en"
    case portugueseBrazil = "pt-BR"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: "English"
        case .portugueseBrazil: "Português (Brasil)"
        }
    }

    var flag: String {
        switch self {
        case .english: "🇺🇸"
        case .portugueseBrazil: "🇧🇷"
        }
    }
}

struct TranslationRequest: Sendable, Equatable {
    var text: String
    var source: TranslationLanguage
    var target: TranslationLanguage
}

enum TranslationOrigin: String, Codable, Sendable {
    case dictionary
    case apple
    case cache

    var displayName: String {
        switch self {
        case .dictionary: "Dicionário local"
        case .apple: "Apple Translation"
        case .cache: "Cache local"
        }
    }

    var icon: String {
        switch self {
        case .dictionary: "book.closed.fill"
        case .apple: "apple.logo"
        case .cache: "bolt.horizontal.circle.fill"
        }
    }
}

struct TranslationResult: Sendable, Equatable {
    var text: String
    /// Other dictionary senses for the same exact lookup. These are shown as
    /// alternatives, never merged into a sentence translation.
    var alternatives: [String] = []
    var source: TranslationLanguage
    var target: TranslationLanguage
    var isOffline: Bool
    var confidence: Double?
    var origin: TranslationOrigin = .dictionary
}

struct TranslationEntry: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var sourceText: String
    var translatedText: String
    var alternatives: [String]
    var source: TranslationLanguage
    var target: TranslationLanguage
    var createdAt: Date
    var isOffline: Bool
    var origin: TranslationOrigin

    private enum CodingKeys: String, CodingKey {
        case id, sourceText, translatedText, alternatives, source, target, createdAt, isOffline, origin
    }

    init(
        sourceText: String,
        translatedText: String,
        alternatives: [String] = [],
        source: TranslationLanguage,
        target: TranslationLanguage,
        createdAt: Date = .now,
        isOffline: Bool = true,
        origin: TranslationOrigin = .dictionary
    ) {
        id = UUID()
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.alternatives = alternatives
        self.source = source
        self.target = target
        self.createdAt = createdAt
        self.isOffline = isOffline
        self.origin = origin
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        sourceText = try values.decode(String.self, forKey: .sourceText)
        translatedText = try values.decode(String.self, forKey: .translatedText)
        alternatives = try values.decodeIfPresent([String].self, forKey: .alternatives) ?? []
        source = try values.decode(TranslationLanguage.self, forKey: .source)
        target = try values.decode(TranslationLanguage.self, forKey: .target)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        isOffline = try values.decodeIfPresent(Bool.self, forKey: .isOffline) ?? true
        origin = try values.decodeIfPresent(TranslationOrigin.self, forKey: .origin) ?? .dictionary
    }
}
