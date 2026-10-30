import AppKit
import ApplicationServices

enum SelectedTextReader {
    static var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    static func readSelectedOrClipboard() -> String? {
        if let selected = selectedText()?.trimmingCharacters(in: .whitespacesAndNewlines), !selected.isEmpty {
            return selected
        }
        return NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func selectedText() -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        // AX calls can block when the foreground app is busy or has no
        // responsive accessibility tree. This path runs from a global
        // shortcut, so keep the fallback to the clipboard responsive.
        _ = AXUIElementSetMessagingTimeout(system, 0.25)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused else { return nil }
        var value: CFTypeRef?
        let focusedElement = element as! AXUIElement
        var focusedPID: pid_t = 0
        if AXUIElementGetPid(focusedElement, &focusedPID) == .success,
           focusedPID == ProcessInfo.processInfo.processIdentifier {
            // Invoking import while our editor is open should use the
            // clipboard, not re-import a selection from the old translation.
            return nil
        }
        _ = AXUIElementSetMessagingTimeout(focusedElement, 0.25)
        guard AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    @MainActor static func requestAccessibilityAccess() {
        // The public constant is imported as mutable global state under Swift 6.
        // Its documented key is stable, so use the literal to keep this helper
        // concurrency-safe without touching the global variable.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
