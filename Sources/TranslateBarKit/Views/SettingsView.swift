import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var history: HistoryStore
    @ObservedObject private var shortcuts: ShortcutStore
    private let onRecordingChanged: (Bool) -> Void
    @State private var launchError: String?
    @State private var accessibilityTrusted = false

    init(
        history: HistoryStore,
        shortcuts: ShortcutStore,
        onRecordingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        _history = ObservedObject(wrappedValue: history)
        _shortcuts = ObservedObject(wrappedValue: shortcuts)
        self.onRecordingChanged = onRecordingChanged
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { enabled in
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    launchError = nil
                } catch {
                    launchError = error.localizedDescription
                }
            }
        )
    }

    var body: some View {
        Form {
            Section("Geral") {
                Toggle("Abrir com o macOS", isOn: launchAtLogin)
                Text("O ícone da barra de menus fica disponível enquanto o app está aberto.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let launchError {
                    Label(launchError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Label("Atalhos configuráveis", systemImage: "keyboard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Toggle("Abrir e focar", isOn: $shortcuts.openShortcutEnabled)
                    Spacer(minLength: 10)
                    ShortcutRecorder(title: "", shortcut: $shortcuts.openShortcut) { recording in
                        updateRecordingState(recording)
                    }
                    .disabled(!shortcuts.openShortcutEnabled)
                }
                HStack {
                    Toggle("Abrir com seleção", isOn: $shortcuts.importShortcutEnabled)
                    Spacer(minLength: 10)
                    ShortcutRecorder(title: "", shortcut: $shortcuts.importShortcut) { recording in
                        updateRecordingState(recording)
                    }
                    .disabled(!shortcuts.importShortcutEnabled)
                }
                if let registrationError = shortcuts.registrationError {
                    Label(registrationError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if accessibilityTrusted {
                    Label("Permissão para ler texto selecionado concedida", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Button("Permitir ler texto selecionado…") {
                        SelectedTextReader.requestAccessibilityAccess()
                        accessibilityTrusted = SelectedTextReader.accessibilityTrusted
                    }
                }
                Text("O segundo atalho tenta ler o texto selecionado no app ativo. Sem permissão de Acessibilidade, ele usa o texto atual da área de transferência.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Tradução") {
                Toggle("Detectar idioma automaticamente", isOn: $model.automaticallyDetectLanguage)
                Text("Quando ativado, o texto colado pode inverter automaticamente inglês e português conforme a direção detectada.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Dados") {
                LabeledContent("Itens no histórico") { Text("\(history.entries.count)") }
                Button("Apagar histórico", role: .destructive) { history.clear() }
                    .disabled(history.entries.isEmpty)
            }

            Section {
                Button("Encerrar Translate Bar", role: .destructive) {
                    NSApp.terminate(nil)
                }
            } footer: {
                Text("O app fica ativo na barra de menus até ser encerrado.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .nativeGlassButtonStyle()
        .frame(maxWidth: .infinity, minHeight: 540, maxHeight: 600)
        .onAppear {
            accessibilityTrusted = SelectedTextReader.accessibilityTrusted
        }
        .task {
            // macOS does not send a reliable notification when the user
            // grants Accessibility in System Settings. Poll only while this
            // preferences view is alive, so the button updates without
            // keeping a background timer in the menu bar app.
            while !Task.isCancelled {
                accessibilityTrusted = SelectedTextReader.accessibilityTrusted
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func updateRecordingState(_ recording: Bool) {
        if recording {
            shortcuts.suspend()
        } else {
            shortcuts.resume()
        }
        onRecordingChanged(recording)
    }
}
