import Foundation

#if canImport(Translation)
@preconcurrency import Translation
#endif

@MainActor
final class AppModel: ObservableObject {
    @Published var sourceText = "" {
        didSet {
            guard sourceText != oldValue, !isApplyingState else { return }
            manualDirectionOverride = false
            invalidatePendingTranslation(clearOutput: true)
            scheduleDebouncedTranslation()
        }
    }
    @Published private(set) var translatedText = ""
    @Published var sourceLanguage: TranslationLanguage = .english {
        didSet {
            guard sourceLanguage != oldValue, !isApplyingState else { return }
            manualDirectionOverride = true
            ensureDistinctLanguages(changed: .source)
            invalidatePendingTranslation(clearOutput: true)
        }
    }
    @Published var targetLanguage: TranslationLanguage = .portugueseBrazil {
        didSet {
            guard targetLanguage != oldValue, !isApplyingState else { return }
            manualDirectionOverride = true
            ensureDistinctLanguages(changed: .target)
            invalidatePendingTranslation(clearOutput: true)
        }
    }
    @Published var automaticallyDetectLanguage: Bool {
        didSet { preferenceDefaults.set(automaticallyDetectLanguage, forKey: Self.automaticDetectionKey) }
    }
    @Published private(set) var isTranslating = false
    @Published var errorMessage: String?
    @Published private(set) var lastResult: TranslationResult?

    let history: HistoryStore
    let translationEngine: TranslationEngine

    private var translationTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var requestGeneration = 0
    private var pendingRequest: TranslationRequest?
    private var claimedGeneration: Int?
    private var isApplyingState = false
    private var manualDirectionOverride = false
    private let detector = LanguageDirectionDetector()
    private let preferenceDefaults: UserDefaults

    private static let automaticDetectionKey = "automaticallyDetectLanguage"
    private static let debounceNanoseconds: UInt64 = 350_000_000

    @Published private(set) var translationRequestID = 0

    init(
        translationEngine: TranslationEngine = TranslationEngine(),
        history: HistoryStore = HistoryStore(),
        defaults: UserDefaults = .standard
    ) {
        self.translationEngine = translationEngine
        self.history = history
        self.preferenceDefaults = defaults
        self.automaticallyDetectLanguage = defaults.object(forKey: Self.automaticDetectionKey) as? Bool ?? true
    }

    var canTranslate: Bool {
        !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isTranslating
    }

    var originLabel: String? { lastResult?.origin.displayName }
    var alternatives: [String] { lastResult?.alternatives ?? [] }
    /// Kept as a compatibility surface until the app delegate owns hot-key
    /// status presentation. Registration itself no longer belongs to the model.
    var hotkeyErrorMessage: String? { nil }

    func requestInputFocus() {
        focusRequestID &+= 1
    }

    @Published private(set) var focusRequestID = 0
    @Published private(set) var editorReplacementID = 0
    let editorReplacementOwnerID = UUID()

    /// Used by paste and shortcut actions. It bypasses the typing debounce.
    func pasteText(_ text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        isApplyingState = true
        sourceText = text
        isApplyingState = false
        manualDirectionOverride = false
        invalidatePendingTranslation(clearOutput: true)
        applyAutomaticDirectionIfNeeded()
        requestInputFocus()
        translate()
    }

    /// Marks an outside replacement before changing the bound text. The editor
    /// uses this token to invalidate delayed NSTextView paste callbacks that
    /// belong to the old document.
    func replaceTextFromShortcut(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        notifyEditorReplacement(text)
        pasteText(text)
    }

    func translate() {
        debounceTask?.cancel()
        debounceTask = nil
        applyAutomaticDirectionIfNeeded()
        translationTask?.cancel()
        requestGeneration += 1
        errorMessage = nil
        let request = TranslationRequest(text: sourceText, source: sourceLanguage, target: targetLanguage)
        guard !request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = TranslationEngineError.emptyInput.localizedDescription
            return
        }
        pendingRequest = request
        claimedGeneration = nil
        isTranslating = true
        startEngineTranslation(request, generation: requestGeneration)
    }

    private func startEngineTranslation(_ request: TranslationRequest, generation: Int) {
        let engine = translationEngine
        translationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await engine.translate(request)
                try Task.checkCancellation()
                apply(result, for: request, generation: generation)
            } catch is CancellationError {
                return
            } catch TranslationEngineError.systemTranslationRequired {
                guard requestGeneration == generation, pendingRequest == request else { return }
                #if canImport(Translation)
                if #available(macOS 15.0, *) {
                    startSystemTranslation(request, generation: generation)
                    return
                }
                #endif
                apply(error: TranslationEngineError.systemTranslationRequired, generation: generation)
            } catch {
                apply(error: error, generation: generation)
            }
        }
    }

    #if canImport(Translation)
    @available(macOS 15.0, *)
    private func startSystemTranslation(_ request: TranslationRequest, generation: Int) {
        translationTask = Task { [weak self] in
            guard let self else { return }
            let status = await SystemTranslationSupport.status(for: request)
            guard requestGeneration == generation, pendingRequest == request else { return }
            switch status {
            case .installed:
                if #available(macOS 26.0, *) {
                    startDirectSystemTranslation(request, generation: generation)
                } else {
                    translationRequestID += 1
                }
            case .supported:
                translationRequestID += 1
            case .unsupported:
                apply(error: TranslationEngineError.unsupportedLanguagePair, generation: generation)
            @unknown default:
                apply(error: TranslationEngineError.unsupportedLanguagePair, generation: generation)
            }
        }
    }

    @available(macOS 26.0, *)
    private func startDirectSystemTranslation(_ request: TranslationRequest, generation: Int) {
        let session = TranslationSession(
            installedSource: SystemTranslationSupport.language(for: request.source),
            target: SystemTranslationSupport.language(for: request.target)
        )
        let engine = translationEngine
        translationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await engine.translate(request, using: session)
                try Task.checkCancellation()
                apply(result, for: request, generation: generation)
            } catch is CancellationError {
                return
            } catch {
                apply(error: error, generation: generation)
            }
        }
    }
    #endif

    private func apply(_ result: TranslationResult, for request: TranslationRequest, generation: Int) {
        guard requestGeneration == generation, pendingRequest == request else { return }
        translatedText = result.text
        lastResult = result
        history.append(TranslationEntry(sourceText: request.text, translatedText: result.text, alternatives: result.alternatives, source: request.source, target: request.target, isOffline: result.isOffline, origin: result.origin))
        pendingRequest = nil
        claimedGeneration = nil
        isTranslating = false
    }

    private func apply(error: Error, generation: Int) {
        guard requestGeneration == generation else { return }
        errorMessage = error.localizedDescription
        pendingRequest = nil
        claimedGeneration = nil
        isTranslating = false
    }

    #if canImport(Translation)
    @available(macOS 15.0, *)
    func translate(using session: TranslationSession) async {
        guard let request = pendingRequest else { return }
        let generation = requestGeneration
        guard claimedGeneration != generation else { return }
        claimedGeneration = generation
        do {
            // This session is attached to the visible contextual host. Calling
            // prepare here lets macOS ask for missing language downloads at the
            // exact moment the user requested a contextual translation.
            try await session.prepareTranslation()
            guard requestGeneration == generation, pendingRequest == request else { return }
            let result = try await translationEngine.translate(request, using: session)
            apply(result, for: request, generation: generation)
        } catch is CancellationError {
            if requestGeneration == generation, pendingRequest == request {
                pendingRequest = nil
                claimedGeneration = nil
                isTranslating = false
            }
            return
        } catch {
            apply(error: error, generation: generation)
        }
    }
    #endif

    func clear() {
        isApplyingState = true
        notifyEditorReplacement("")
        requestGeneration += 1
        translationTask?.cancel()
        debounceTask?.cancel()
        debounceTask = nil
        sourceText = ""
        isApplyingState = false
        translatedText = ""
        lastResult = nil
        errorMessage = nil
        pendingRequest = nil
        claimedGeneration = nil
        isTranslating = false
    }

    func swapLanguages() {
        isApplyingState = true
        manualDirectionOverride = true
        requestGeneration += 1
        translationTask?.cancel()
        debounceTask?.cancel()
        debounceTask = nil
        let oldSource = sourceLanguage
        sourceLanguage = targetLanguage
        targetLanguage = oldSource
        let oldText = sourceText
        let replacementText = translatedText.isEmpty ? oldText : translatedText
        notifyEditorReplacement(replacementText)
        sourceText = replacementText
        translatedText = ""
        isApplyingState = false
        lastResult = nil
        errorMessage = nil
        pendingRequest = nil
        claimedGeneration = nil
        isTranslating = false
        if !replacementText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            translate()
        }
    }

    func useHistory(_ entry: TranslationEntry) {
        isApplyingState = true
        requestGeneration += 1
        translationTask?.cancel()
        debounceTask?.cancel()
        debounceTask = nil
        sourceLanguage = entry.source
        targetLanguage = entry.target
        notifyEditorReplacement(entry.sourceText)
        sourceText = entry.sourceText
        translatedText = entry.translatedText
        isApplyingState = false
        lastResult = TranslationResult(
            text: entry.translatedText,
            alternatives: entry.alternatives,
            source: entry.source,
            target: entry.target,
            isOffline: entry.isOffline,
            confidence: nil,
            origin: entry.origin
        )
        errorMessage = nil
        pendingRequest = nil
        claimedGeneration = nil
        isTranslating = false
    }

    func chooseAlternative(_ value: String) {
        guard var result = lastResult else { return }
        result.text = value
        translatedText = value
        lastResult = result
    }

    func failSystemTranslation(_ error: Error) {
        pendingRequest = nil
        claimedGeneration = nil
        isTranslating = false
        errorMessage = error.localizedDescription
    }

    private func invalidatePendingTranslation(clearOutput: Bool) {
        requestGeneration += 1
        translationTask?.cancel()
        debounceTask?.cancel()
        debounceTask = nil
        pendingRequest = nil
        claimedGeneration = nil
        isTranslating = false
        errorMessage = nil
        if clearOutput {
            translatedText = ""
            lastResult = nil
        }
    }

    private func notifyEditorReplacement(_ text: String) {
        editorReplacementID &+= 1
        NotificationCenter.default.post(
            name: .translateBarReplaceEditor,
            object: nil,
            userInfo: [
                "owner": editorReplacementOwnerID,
                "id": editorReplacementID,
                "text": text
            ]
        )
    }

    private func scheduleDebouncedTranslation() {
        let expectedText = sourceText
        let expectedGeneration = requestGeneration
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.debounceNanoseconds)
            } catch { return }
            guard let self,
                  self.sourceText == expectedText,
                  self.requestGeneration == expectedGeneration,
                  !self.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            self.applyAutomaticDirectionIfNeeded()
            self.translate()
        }
    }

    private enum LanguageSide { case source, target }

    private func ensureDistinctLanguages(changed side: LanguageSide) {
        guard sourceLanguage == targetLanguage else { return }
        isApplyingState = true
        switch side {
        case .source:
            targetLanguage = sourceLanguage == .english ? .portugueseBrazil : .english
        case .target:
            sourceLanguage = targetLanguage == .english ? .portugueseBrazil : .english
        }
        isApplyingState = false
    }

    private func applyAutomaticDirectionIfNeeded() {
        guard automaticallyDetectLanguage, !manualDirectionOverride,
              let detected = detector.language(for: sourceText), detected != sourceLanguage else { return }
        guard detected == .english || detected == .portugueseBrazil else { return }
        isApplyingState = true
        if detected == targetLanguage {
            let oldSource = sourceLanguage
            sourceLanguage = targetLanguage
            targetLanguage = oldSource
        } else {
            sourceLanguage = detected
            if sourceLanguage == targetLanguage {
                targetLanguage = detected == .english ? .portugueseBrazil : .english
            }
        }
        isApplyingState = false
    }

    deinit {
        translationTask?.cancel()
        debounceTask?.cancel()
    }
}
