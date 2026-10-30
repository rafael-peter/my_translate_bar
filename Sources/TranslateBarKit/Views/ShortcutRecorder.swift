import SwiftUI
import Carbon.HIToolbox

struct ShortcutRecorder: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    @Binding var shortcut: ShortcutDefinition
    var onRecordingChanged: (Bool) -> Void = { _ in }
    @State private var isRecording = false
    @StateObject private var capture = ShortcutCapture()

    var body: some View {
        HStack {
            if !title.isEmpty {
                Text(title)
            }
            Spacer()
            Button(isRecording ? "Pressione as teclas…" : shortcut.displayName) {
                isRecording.toggle()
                if isRecording {
                    capture.start(onCapture: { value in
                        shortcut = value
                        isRecording = false
                        onRecordingChanged(false)
                    }, onCancel: {
                        isRecording = false
                        onRecordingChanged(false)
                    })
                    // Starting this capture cancels the previous recorder,
                    // which resumes shortcuts. Suspend after that cleanup.
                    onRecordingChanged(true)
                } else {
                    capture.stop()
                    onRecordingChanged(false)
                }
            }
            .nativeGlassButtonStyle()
            .controlSize(.small)
        }
        .onDisappear {
            if isRecording {
                capture.cancel()
            } else {
                capture.stop()
            }
        }
        .onChange(of: isEnabled) { _, enabled in
            if !enabled, isRecording { capture.cancel() }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TranslateBar.popoverClosed"))) { _ in
            // A popover can retain its hosting view, so relying on
            // onDisappear alone can leave the local monitor active.
            if isRecording {
                capture.cancel()
            }
        }
    }
}

@MainActor
private final class ShortcutCapture: ObservableObject {
    private static weak var active: ShortcutCapture?
    private var monitor: Any?
    private var cancelHandler: (() -> Void)?

    func start(onCapture: @escaping (ShortcutDefinition) -> Void, onCancel: @escaping () -> Void) {
        // There is only one local key monitor for the recorder UI. Starting a
        // second recorder cancels the first one and lets its view restore the
        // global shortcuts it suspended.
        Self.active?.cancel()
        stop()
        cancelHandler = onCancel
        Self.active = self
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == UInt16(kVK_Escape) {
                Task { @MainActor [weak self] in self?.cancel() }
                return nil
            }
            guard let shortcut = ShortcutDefinition(event: event) else { return event }
            Task { @MainActor [weak self] in
                guard let self, self.monitor != nil else { return }
                self.stop()
                onCapture(shortcut)
            }
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        cancelHandler = nil
        if Self.active === self { Self.active = nil }
    }

    func cancel() {
        let handler = cancelHandler
        stop()
        handler?()
    }

}
