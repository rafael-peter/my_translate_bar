import SwiftUI
import AppKit

struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var shortcuts: ShortcutStore
    @State private var showsSettings = false
    @State private var showsHistory = false
    @State private var copied = false

    var body: some View {
        NativeGlassControls {
            VStack(alignment: .leading, spacing: 12) {
                header
                if showsSettings {
                    SettingsView(history: model.history, shortcuts: shortcuts)
                } else {
                    inputField
                    translationStatus
                    if !model.translatedText.isEmpty {
                        translationCard
                    }
                    if showsHistory {
                        Divider()
                        CompactHistoryView(history: model.history) { entry in
                            model.useHistory(entry)
                            showsHistory = false
                            model.requestInputFocus()
                        }
                    }
                }
                TranslationTaskHost(model: model)
            }
            .padding(16)
            .frame(width: 400)
            .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: model.translatedText) { _, _ in copied = false }
        .onChange(of: model.focusRequestID) { _, _ in showsSettings = false }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TranslateBar.popoverClosed"))) { _ in
            // Removing SettingsView also cancels its permission refresh task.
            showsSettings = false
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if showsSettings {
                Text("Preferências").font(.headline)
                Spacer()
                NativeIconButton(title: "Voltar à tradução", systemImage: "arrow.left") {
                    showsSettings = false
                    model.requestInputFocus()
                }
            } else {
                languageControls
                Spacer(minLength: 8)
                NativeIconButton(title: "Histórico", systemImage: "clock") { showsHistory.toggle() }
                NativeIconButton(title: "Preferências e atalhos", systemImage: "gearshape") { showsSettings = true }
            }
        }
    }

    private var languageControls: some View {
        HStack(spacing: 6) {
            Text(model.sourceLanguage == .english ? "🇺🇸 Inglês" : "🇧🇷 Português")
            NativeIconButton(title: "Inverter idiomas", systemImage: "arrow.left.arrow.right") {
                model.swapLanguages()
                model.requestInputFocus()
            }
            Text(model.targetLanguage == .english ? "🇺🇸 Inglês" : "🇧🇷 Português")
        }
        .font(.callout.weight(.medium))
        .fixedSize()
    }

    private var inputField: some View {
        GrowingTextEditor(
            text: $model.sourceText,
            focusRequestID: model.focusRequestID,
            replacementID: model.editorReplacementID,
            replacementOwnerID: model.editorReplacementOwnerID
        ) { model.pasteText($0) }
        // Keep a dedicated trailing gutter so Clear never covers text or the
        // editor's scrollbar, even with a full 200-point input field.
        .padding(.trailing, 38)
        .padding(4)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.10)))
        .overlay(alignment: .topLeading) {
            if model.sourceText.isEmpty {
                Text("Digite ou cole um texto…")
                    .font(.system(size: 15))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            if !model.sourceText.isEmpty {
                NativeIconButton(title: "Limpar texto", systemImage: "xmark") {
                    model.clear()
                    model.requestInputFocus()
                }
                .padding(7)
            }
        }
    }

    private var translationCard: some View {
        HStack(alignment: .top, spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.translatedText)
                        .font(.system(size: 15))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !model.alternatives.isEmpty {
                        Divider()
                        Text("Outros sentidos").font(.caption).foregroundStyle(.secondary)
                        ForEach(model.alternatives, id: \.self) { alternative in
                            Button(alternative) { model.chooseAlternative(alternative) }
                                .buttonStyle(.link).multilineTextAlignment(.leading)
                        }
                    }
                }
            }
            .frame(maxHeight: 220)
            .fixedSize(horizontal: false, vertical: true)

            NativeIconButton(title: copied ? "Tradução copiada" : "Copiar tradução", systemImage: copied ? "checkmark" : "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(model.translatedText, forType: .string)
                copied = true
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 7)
        .padding(.top, 2)
    }

    @ViewBuilder
    private var translationStatus: some View {
        if model.isTranslating {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Traduzindo…").font(.caption).foregroundStyle(.secondary)
            }
        } else if let error = model.errorMessage {
            HStack(spacing: 8) {
                Text(error).font(.caption).foregroundStyle(.orange).lineLimit(3)
                Spacer(minLength: 0)
                NativeIconButton(title: "Tentar novamente", systemImage: "arrow.clockwise") { model.translate() }
            }
        }
    }
}

private struct CompactHistoryView: View {
    @ObservedObject var history: HistoryStore
    var select: (TranslationEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Histórico").font(.caption.weight(.semibold))
                Spacer()
                Button("Limpar") { history.clear() }.buttonStyle(.borderless)
                    .disabled(history.entries.isEmpty)
            }
            if history.entries.isEmpty {
                Text("Suas traduções aparecem aqui.").font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(history.entries) { entry in
                            Button { select(entry) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.sourceText).lineLimit(1)
                                    Text(entry.translatedText).lineLimit(1).foregroundStyle(.secondary)
                                }.font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                            }.buttonStyle(.plain)
                            Divider()
                        }
                    }
                }.frame(maxHeight: 180)
            }
        }
    }
}
