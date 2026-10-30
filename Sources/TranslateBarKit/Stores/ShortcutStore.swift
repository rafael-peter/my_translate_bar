import AppKit
import Carbon.HIToolbox
import Combine

struct ShortcutDefinition: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let openDefault = ShortcutDefinition(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(cmdKey | shiftKey)
    )
    static let importDefault = ShortcutDefinition(
        keyCode: UInt32(kVK_ANSI_V),
        modifiers: UInt32(controlKey | optionKey)
    )

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init?(event: NSEvent) {
        let meaningfulModifiers: NSEvent.ModifierFlags = [.command, .option, .control]
        guard !event.modifierFlags.intersection(meaningfulModifiers).isEmpty else { return nil }
        keyCode = UInt32(event.keyCode)
        var value: UInt32 = 0
        if event.modifierFlags.contains(.command) { value |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.option) { value |= UInt32(optionKey) }
        if event.modifierFlags.contains(.control) { value |= UInt32(controlKey) }
        if event.modifierFlags.contains(.shift) { value |= UInt32(shiftKey) }
        modifiers = value
    }

    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        return flags
    }

    var displayName: String {
        let prefix = [
            modifierFlags.contains(.control) ? "⌃" : "",
            modifierFlags.contains(.option) ? "⌥" : "",
            modifierFlags.contains(.shift) ? "⇧" : "",
            modifierFlags.contains(.command) ? "⌘" : ""
        ].joined()
        let key: String
        switch keyCode {
        case UInt32(kVK_Space): key = "Espaço"
        case UInt32(kVK_Return): key = "Return"
        case UInt32(kVK_Delete): key = "Delete"
        default: key = Self.keyNames[keyCode] ?? "Tecla \(keyCode)"
        }
        return prefix + key
    }

    private static let keyNames: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9"
    ]
}

@MainActor
final class ShortcutStore: ObservableObject {
    @Published var openShortcut: ShortcutDefinition { didSet { save(); restart() } }
    @Published var importShortcut: ShortcutDefinition { didSet { save(); restart() } }
    /// Each shortcut can be turned off without losing its configured key
    /// combination. This keeps the recorder useful when the user wants to
    /// temporarily disable a global action.
    @Published var openShortcutEnabled: Bool { didSet { save(); restart() } }
    @Published var importShortcutEnabled: Bool { didSet { save(); restart() } }
    @Published private(set) var registrationError: String?

    private let defaults: UserDefaults
    private let onOpen: () -> Void
    private let onImport: () -> Void
    private let registerImmediately: Bool
    /// Published so the popover presenter can avoid treating Escape as a
    /// request to close while a shortcut is being recorded.
    @Published private(set) var isSuspended = false
    private var openController: GlobalHotkeyController?
    private var importController: GlobalHotkeyController?

    init(
        onOpen: @escaping () -> Void = {},
        onImport: @escaping () -> Void = {},
        defaults: UserDefaults = .standard,
        registerImmediately: Bool = true
    ) {
        self.onOpen = onOpen
        self.onImport = onImport
        self.defaults = defaults
        self.registerImmediately = registerImmediately
        let data = defaults.data(forKey: "translateBar.shortcuts.v1")
        let saved = data.flatMap { try? JSONDecoder().decode([String: ShortcutDefinition].self, from: $0) }
        openShortcut = saved?["open"] ?? .openDefault
        importShortcut = saved?["import"] ?? .importDefault
        // Older settings did not have enabled flags. Preserve their behavior
        // by treating both existing shortcuts as enabled during migration.
        openShortcutEnabled = defaults.object(forKey: "translateBar.shortcuts.openEnabled.v1") as? Bool ?? true
        importShortcutEnabled = defaults.object(forKey: "translateBar.shortcuts.importEnabled.v1") as? Bool ?? true
        if registerImmediately { restart() }
    }

    func resetToDefaults() {
        openShortcut = .openDefault
        importShortcut = .importDefault
    }

    func restart() {
        guard registerImmediately, !isSuspended else { return }
        openController?.stop()
        importController?.stop()
        registrationError = nil
        do {
            let open = openShortcutEnabled
                ? GlobalHotkeyController(keyCode: openShortcut.keyCode, modifiers: openShortcut.modifiers, eventID: 1, eventSignature: 0x4D545231, onPress: onOpen)
                : nil
            let imported = importShortcutEnabled
                ? GlobalHotkeyController(keyCode: importShortcut.keyCode, modifiers: importShortcut.modifiers, eventID: 2, eventSignature: 0x4D545232, onPress: onImport)
                : nil
            do {
                try open?.start()
                try imported?.start()
                openController = open
                importController = imported
            } catch {
                // If the second registration fails, explicitly release the
                // first registration too; Carbon does not own our object.
                open?.stop()
                imported?.stop()
                throw error
            }
        } catch {
            registrationError = error.localizedDescription
        }
    }

    func suspend() {
        isSuspended = true
        openController?.stop()
        importController?.stop()
    }

    func resume() {
        isSuspended = false
        restart()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(["open": openShortcut, "import": importShortcut]) else { return }
        defaults.set(data, forKey: "translateBar.shortcuts.v1")
        defaults.set(openShortcutEnabled, forKey: "translateBar.shortcuts.openEnabled.v1")
        defaults.set(importShortcutEnabled, forKey: "translateBar.shortcuts.importEnabled.v1")
    }

    deinit {
        let open = openController
        let imported = importController
        Task { @MainActor in
            open?.stop()
            imported?.stop()
        }
    }
}
