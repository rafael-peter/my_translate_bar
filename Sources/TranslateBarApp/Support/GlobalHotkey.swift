import AppKit
import Carbon.HIToolbox

extension Notification.Name {
    static let translateBarShowMainWindow = Notification.Name("TranslateBar.showMainWindow")
}

/// A small Carbon bridge for an application-wide keyboard shortcut.
///
/// Carbon delivers hot-key events on the application event loop, so callers
/// must create, start, and stop this object on the main actor. The default
/// shortcut is Command-Shift-Space. Registration is intentionally explicit:
/// callers can show `GlobalHotkeyError.localizedDescription` when another app
/// already owns the shortcut or the system rejects it.
@MainActor
final class GlobalHotkeyController: NSObject {
    typealias Handler = () -> Void

    private static let defaultEventSignature: OSType = 0x4D545242 // “MTRB”

    private let keyCode: UInt32
    private let modifiers: UInt32
    private let eventSignature: OSType
    private let eventID: UInt32
    private let onPress: Handler
    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?

    init(
        keyCode: UInt32 = UInt32(kVK_Space),
        modifiers: UInt32 = UInt32(cmdKey | shiftKey),
        eventID: UInt32 = 1,
        eventSignature: OSType = GlobalHotkeyController.defaultEventSignature,
        onPress: @escaping Handler
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.eventID = eventID
        self.eventSignature = eventSignature
        self.onPress = onPress
    }

    deinit {
        // `stop()` is main-actor isolated. Carbon cleanup is only needed when
        // the owner explicitly stops the controller before releasing it.
    }

    var isRegistered: Bool { hotKeyReference != nil }

    func start() throws {
        guard hotKeyReference == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            GlobalHotkeyController.eventHandler,
            1,
            &eventType,
            userData,
            &eventHandlerReference
        )
        guard installStatus == noErr else {
            throw GlobalHotkeyError.eventHandlerInstallationFailed(installStatus)
        }

        let identifier = EventHotKeyID(signature: eventSignature, id: eventID)
        let registrationStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )
        guard registrationStatus == noErr else {
            RemoveEventHandler(eventHandlerReference)
            eventHandlerReference = nil
            throw GlobalHotkeyError.registrationFailed(registrationStatus)
        }
    }

    func stop() {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
            self.hotKeyReference = nil
        }
        if let eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
            self.eventHandlerReference = nil
        }
    }

    private func handlePress() {
        onPress()
    }

    private static let eventHandler: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }

        let controller = Unmanaged<GlobalHotkeyController>
            .fromOpaque(userData)
            .takeUnretainedValue()
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr,
              hotKeyID.signature == controller.eventSignature,
              hotKeyID.id == controller.eventID else {
            return OSStatus(eventNotHandledErr)
        }
        Task { @MainActor in
            controller.handlePress()
        }
        return noErr
    }
}

enum GlobalHotkeyError: LocalizedError, Sendable {
    case eventHandlerInstallationFailed(OSStatus)
    case registrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .eventHandlerInstallationFailed(status):
            "Não foi possível preparar o atalho global (código \(status))."
        case let .registrationFailed(status):
            "Não foi possível registrar o atalho global. Ele pode estar em uso por outro app (código \(status))."
        }
    }
}
