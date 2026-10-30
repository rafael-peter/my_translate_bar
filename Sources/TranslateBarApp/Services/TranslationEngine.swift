import Foundation

#if canImport(Translation)
@preconcurrency import Translation
#endif

/// A translation service that always tries the local dictionary first.
///
/// The dictionary is intentionally limited to exact phrases and word level
/// lookups. It is useful for the high frequency, one word lookups that should
/// feel instant, but it must not be presented as a grammar aware translator.
protocol TranslationService: Sendable {
    func translate(_ request: TranslationRequest) async throws -> TranslationResult
}

enum TranslationEngineError: LocalizedError, Sendable {
    case emptyInput
    case unsupportedLanguagePair
    case systemTranslationRequired
    case systemTranslationFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            "Digite algo para traduzir."
        case .unsupportedLanguagePair:
            "Este par de idiomas ainda não está disponível."
        case .systemTranslationRequired:
            "A tradução desta frase precisa do tradutor do macOS."
        case let .systemTranslationFailed(message):
            message
        }
    }
}

#if canImport(Translation)
/// Helpers for the public macOS Translation framework. The framework creates
/// a session in SwiftUI's `translationTask`; the app should check status and
/// call `prepareTranslation()` there before sending the first long sentence.
@available(macOS 15.0, *)
enum SystemTranslationSupport {
    static func language(for value: TranslationLanguage) -> Locale.Language {
        Locale.Language(identifier: value.rawValue)
    }

    static func configuration(for request: TranslationRequest) -> TranslationSession.Configuration {
        TranslationSession.Configuration(
            source: language(for: request.source),
            target: language(for: request.target)
        )
    }

    static func status(for request: TranslationRequest) async -> LanguageAvailability.Status {
        await LanguageAvailability().status(
            from: language(for: request.source),
            to: language(for: request.target)
        )
    }
}
#endif

/// Small, dependency-free dictionary used for instant lookups and as a cache
/// seed. A larger JSON dictionary can be shipped later without changing the
/// engine contract (`OfflineDictionary(contentsOf:)`).
struct OfflineDictionary: Sendable {
    private var values: [String: String]
    private var directionalValues: [String: [String]]

    init(values: [String: String] = OfflineDictionary.defaultValues) {
        self.values = values.reduce(into: [:]) { result, item in
            result[Self.key(item.key)] = item.value
        }
        self.directionalValues = Self.directionalDefaults
    }

    private init(values: [String: String], directionalValues: [String: [String]]) {
        self.values = values
        self.directionalValues = directionalValues
    }

    init(directionalEntries: [TranslationLanguage: [TranslationLanguage: [String: [String]]]]) {
        self.values = [:]
        self.directionalValues = directionalEntries.reduce(into: [:]) { result, sourceEntry in
            for targetEntry in sourceEntry.value {
                for (word, meanings) in targetEntry.value where !meanings.isEmpty {
                    result[Self.directionalKey(Self.key(word), source: sourceEntry.key, target: targetEntry.key)] = meanings
                }
            }
        }
    }

    init(contentsOf url: URL, replacingValues: Bool = false) throws {
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode([String: String].self, from: data)
        self.init(values: replacingValues ? decoded : Self.defaultValues.merging(decoded) { _, newer in newer })
    }

    /// Loads the bundled FreeDict snapshots when present. The app still has a
    /// small built-in dictionary, so a missing or malformed resource never
    /// prevents the menu bar app from starting.
    static func bundled() -> OfflineDictionary {
        let fallback = OfflineDictionary()
        var directional = fallback.directionalValues
        let files = [
            ("freedict-en-pt", TranslationLanguage.english, TranslationLanguage.portugueseBrazil),
            ("freedict-pt-en", TranslationLanguage.portugueseBrazil, TranslationLanguage.english)
        ]
        for (name, source, target) in files {
            guard let url = Bundle.module.url(forResource: name, withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let payload = try? JSONDecoder().decode(FreeDictPayload.self, from: data) else { continue }
            for (word, meanings) in payload.entries {
                let alternatives = meanings.filter { !$0.isEmpty }
                guard !alternatives.isEmpty else { continue }
                directional[directionalKey(key(word), source: source, target: target)] = alternatives
            }
        }
        return OfflineDictionary(values: fallback.values, directionalValues: directional)
    }

    func lookup(_ text: String) -> String? {
        values[Self.key(text)]
    }

    func lookup(_ text: String, source: TranslationLanguage, target: TranslationLanguage) -> String? {
        lookupAlternatives(text, source: source, target: target)?.first
    }

    func lookupAlternatives(_ text: String, source: TranslationLanguage, target: TranslationLanguage) -> [String]? {
        let normalized = Self.key(text)
        return directionalValues[Self.directionalKey(normalized, source: source, target: target)]
    }

    func merging(_ other: OfflineDictionary) -> OfflineDictionary {
        OfflineDictionary(values: values.merging(other.values) { _, newer in newer })
    }

    private static func key(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .folding(options: [.caseInsensitive], locale: .current)
            .lowercased()
    }

    private static func directionalKey(_ value: String, source: TranslationLanguage, target: TranslationLanguage) -> String {
        "\(source.rawValue)>\(target.rawValue)|\(value)"
    }

    private static let directionalDefaults: [String: [String]] = {
        let enPT: [String: String] = [
            "hello":"olá", "hi":"oi", "good morning":"bom dia", "good afternoon":"boa tarde", "good evening":"boa noite", "good night":"boa noite", "goodbye":"tchau", "please":"por favor", "thanks":"obrigado", "thank you":"obrigado", "yes":"sim", "no":"não", "maybe":"talvez", "help":"ajuda", "welcome":"bem-vindo", "sorry":"desculpe", "excuse me":"com licença", "save":"salvar", "cancel":"cancelar", "close":"fechar", "open":"abrir", "copy":"copiar", "paste":"colar", "search":"pesquisar", "settings":"configurações", "preferences":"preferências", "language":"idioma", "languages":"idiomas", "translate":"traduzir", "translation":"tradução", "text":"texto", "word":"palavra", "sentence":"frase", "history":"histórico", "favorite":"favorito", "online":"online", "offline":"offline", "ready":"pronto", "error":"erro", "loading":"carregando", "computer":"computador", "application":"aplicativo", "window":"janela", "screen":"tela", "keyboard":"teclado", "shortcut":"atalho", "performance":"desempenho", "fast":"rápido", "slow":"lento", "today":"hoje", "tomorrow":"amanhã", "yesterday":"ontem", "time":"tempo", "day":"dia", "one":"um", "two":"dois", "three":"três", "four":"quatro", "five":"cinco", "and":"e", "or":"ou", "but":"mas", "the":"o", "a":"um", "an":"um", "of":"de", "to":"para", "from":"de", "in":"em", "on":"em", "with":"com", "for":"para", "is":"é", "are":"são", "was":"era", "be":"ser", "have":"ter", "can":"pode", "what":"o que", "where":"onde", "when":"quando", "why":"por que", "how":"como"
        ]
        let ptEN: [String: String] = [
            "olá":"hello", "oi":"hi", "bom dia":"good morning", "boa tarde":"good afternoon", "boa noite":"good evening", "tchau":"goodbye", "por favor":"please", "obrigado":"thank you", "obrigada":"thank you", "sim":"yes", "não":"no", "talvez":"maybe", "ajuda":"help", "bem-vindo":"welcome", "desculpe":"sorry", "com licença":"excuse me", "salvar":"save", "cancelar":"cancel", "fechar":"close", "abrir":"open", "copiar":"copy", "colar":"paste", "pesquisar":"search", "configurações":"settings", "preferências":"preferences", "idioma":"language", "idiomas":"languages", "traduzir":"translate", "tradução":"translation", "texto":"text", "palavra":"word", "frase":"sentence", "histórico":"history", "favorito":"favorite", "pronto":"ready", "erro":"error", "carregando":"loading", "computador":"computer", "aplicativo":"application", "janela":"window", "tela":"screen", "teclado":"keyboard", "atalho":"shortcut", "desempenho":"performance", "rápido":"fast", "lento":"slow", "hoje":"today", "amanhã":"tomorrow", "ontem":"yesterday", "tempo":"time", "dia":"day", "um":"one", "dois":"two", "três":"three", "quatro":"four", "cinco":"five", "e":"and", "ou":"or", "mas":"but", "o":"the", "a":"the", "de":"of", "para":"to", "em":"in", "com":"with", "é":"is", "são":"are", "era":"was", "ser":"be", "ter":"have", "pode":"can", "o que":"what", "onde":"where", "quando":"when", "por que":"why", "como":"how"
        ]
        var result: [String: [String]] = [:]
        enPT.forEach { result[directionalKey(key($0.key), source: .english, target: .portugueseBrazil)] = [$0.value] }
        ptEN.forEach { result[directionalKey(key($0.key), source: .portugueseBrazil, target: .english)] = [$0.value] }
        return result
    }()

    private static let defaultValues: [String: String] = [
        // Common UI and computer terms.
        "hello": "olá", "hi": "oi", "good morning": "bom dia", "good afternoon": "boa tarde",
        "good evening": "boa noite", "good night": "boa noite", "goodbye": "tchau", "please": "por favor",
        "thanks": "obrigado", "thank you": "obrigado", "yes": "sim", "no": "não", "maybe": "talvez",
        "help": "ajuda", "welcome": "bem-vindo", "sorry": "desculpe", "excuse me": "com licença",
        "save": "salvar", "cancel": "cancelar", "close": "fechar", "open": "abrir", "copy": "copiar",
        "paste": "colar", "search": "pesquisar", "settings": "configurações", "preferences": "preferências",
        "language": "idioma", "languages": "idiomas", "translate": "traduzir", "translation": "tradução",
        "text": "texto", "word": "palavra", "sentence": "frase", "history": "histórico", "favorite": "favorito",
        "online": "online", "offline": "offline", "ready": "pronto", "error": "erro", "loading": "carregando",
        "computer": "computador", "application": "aplicativo", "window": "janela", "screen": "tela",
        "keyboard": "teclado", "shortcut": "atalho", "performance": "desempenho", "fast": "rápido", "slow": "lento",
        "today": "hoje", "tomorrow": "amanhã", "yesterday": "ontem", "time": "tempo", "day": "dia",
        "one": "um", "two": "dois", "three": "três", "four": "quatro", "five": "cinco",
        "and": "e", "or": "ou", "but": "mas", "the": "o", "a": "a", "an": "um", "of": "de",
        "to": "para", "from": "de", "in": "em", "on": "em", "with": "com", "for": "para",
        "is": "é", "are": "são", "was": "era", "be": "ser", "have": "ter", "can": "pode",
        "what": "o que", "where": "onde", "when": "quando", "why": "por que", "how": "como",

        // Reverse direction. Keeping both directions local is useful for the
        // menu bar workflow, where source language detection is not required.
        "olá": "hello", "oi": "hi", "bom dia": "good morning", "boa tarde": "good afternoon",
        "boa noite": "good evening", "tchau": "goodbye", "por favor": "please", "obrigado": "thank you",
        "sim": "yes", "não": "no", "talvez": "maybe", "ajuda": "help", "bem-vindo": "welcome",
        "desculpe": "sorry", "com licença": "excuse me", "salvar": "save", "cancelar": "cancelar",
        "fechar": "close", "abrir": "open", "copiar": "copy", "colar": "paste", "pesquisar": "search",
        "configurações": "settings", "preferências": "preferences", "idioma": "language", "idiomas": "languages",
        "traduzir": "translate", "tradução": "translation", "texto": "text", "palavra": "word", "frase": "sentence",
        "histórico": "history", "favorito": "favorite", "pronto": "ready", "erro": "error", "carregando": "loading",
        "computador": "computer", "aplicativo": "application", "janela": "window", "tela": "screen", "teclado": "keyboard",
        "atalho": "shortcut", "desempenho": "performance", "rápido": "fast", "lento": "slow", "hoje": "today",
        "amanhã": "tomorrow", "ontem": "yesterday", "tempo": "time", "dia": "day", "um": "one", "dois": "two",
        "três": "three", "quatro": "four", "cinco": "five", "e": "and", "ou": "or", "mas": "but", "o": "the",
        "de": "of", "para": "to", "em": "in", "com": "with", "é": "is", "são": "are", "era": "was", "ser": "be",
        "ter": "have", "pode": "can", "o que": "what", "onde": "where", "quando": "when", "por que": "why", "como": "how"
    ]

    private struct FreeDictPayload: Codable {
        let entries: [String: [String]]
    }
}

actor TranslationEngine: TranslationService {
    private struct CacheKey: Hashable, Sendable {
        let text: String
        let source: TranslationLanguage
        let target: TranslationLanguage
    }

    private let dictionary: OfflineDictionary
    private var cache: [CacheKey: TranslationResult] = [:]
    private let maxCacheEntries = 256

    init(dictionary: OfflineDictionary = OfflineDictionary.bundled()) {
        self.dictionary = dictionary
    }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        try validate(request)
        let key = CacheKey(text: cacheKeyText(request.text), source: request.source, target: request.target)
        if let cached = cache[key] {
            var result = cached
            result.origin = .cache
            return result
        }

        if let local = localTranslation(for: request) {
            store(local, for: key)
            return local
        }
        throw TranslationEngineError.systemTranslationRequired
    }

    /// Uses a `TranslationSession` supplied by SwiftUI's `translationTask`.
    /// Apple's public API creates sessions through that view modifier on macOS
    /// 15, so the engine deliberately accepts the session instead of trying to
    /// construct one through a private initializer.
    #if canImport(Translation)
    @available(macOS 15.0, *)
    func translate(_ request: TranslationRequest, using session: TranslationSession) async throws -> TranslationResult {
        try validate(request)
        let key = CacheKey(text: cacheKeyText(request.text), source: request.source, target: request.target)
        if let cached = cache[key] {
            var result = cached
            result.origin = .cache
            return result
        }

        if let local = localTranslation(for: request) {
            store(local, for: key)
            return local
        }

        do {
            let response = try await session.translate(request.text)
            let result = TranslationResult(
                text: response.targetText,
                source: request.source,
                target: request.target,
                isOffline: true,
                confidence: nil,
                origin: .apple
            )
            store(result, for: key)
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw TranslationEngineError.systemTranslationFailed(error.localizedDescription)
        }
    }
    #endif

    func clearCache() {
        cache.removeAll(keepingCapacity: true)
    }

    var cacheCount: Int { cache.count }

    private func store(_ result: TranslationResult, for key: CacheKey) {
        if cache.count >= maxCacheEntries, cache[key] == nil, let oldest = cache.keys.first {
            cache.removeValue(forKey: oldest)
        }
        cache[key] = result
    }

    #if canImport(Translation)
    @available(macOS 15.0, *)
    func prepareSystemTranslation(using session: TranslationSession) async throws {
        try await session.prepareTranslation()
    }
    #endif

    private func validate(_ request: TranslationRequest) throws {
        guard !request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationEngineError.emptyInput
        }
        guard request.source != request.target else {
            throw TranslationEngineError.unsupportedLanguagePair
        }
    }

    private func localTranslation(for request: TranslationRequest) -> TranslationResult? {
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let exact = dictionary.lookup(text, source: request.source, target: request.target) else { return nil }
        return TranslationResult(
            text: exact,
            alternatives: Array(dictionary.lookupAlternatives(text, source: request.source, target: request.target)?.dropFirst() ?? []),
            source: request.source,
            target: request.target,
            isOffline: true,
            confidence: nil,
            origin: .dictionary
        )
    }

    private func cacheKeyText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}

