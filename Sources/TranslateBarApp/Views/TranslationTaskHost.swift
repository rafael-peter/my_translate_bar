import SwiftUI
@preconcurrency import Translation

/// This host exists only inside the status-bar popover. It requests a session
/// only when the model has a contextual request requiring system UI.
struct TranslationTaskHost: View {
    @ObservedObject var model: AppModel
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        Color.clear.frame(height: 0)
            .translationTask(configuration) { session in
                await model.translate(using: session)
            }
            .onChange(of: model.translationRequestID) { _, _ in
                let source = Locale.Language(identifier: model.sourceLanguage.rawValue)
                let target = Locale.Language(identifier: model.targetLanguage.rawValue)
                if configuration?.source == source && configuration?.target == target {
                    configuration?.invalidate()
                } else {
                    configuration = TranslationSession.Configuration(source: source, target: target)
                }
            }
            .onDisappear { configuration = nil }
    }
}
