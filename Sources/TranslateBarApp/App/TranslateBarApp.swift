import SwiftUI
import AppKit
import OSLog

@main
struct TranslateBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

/// AppKit owns only the status item/popover and activation; all content and
/// translation state remain in SwiftUI and AppModel.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var shortcuts: ShortcutStore?
    private let logger = Logger(subsystem: "com.mytranslatebar.app", category: "Popover")
    /// Events delivered to the app that owns the popover are not reported to
    /// a global monitor. We keep the monitor around for the complementary
    /// case: a click in the app that was active before the global shortcut
    /// opened Translate Bar. This is also what lets an application-defined
    /// popover retain its window while a fullscreen Space is active.
    private var outsideEventMonitor: Any?
    private var localEscapeMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let shortcuts = ShortcutStore(
            onOpen: { [weak self] in
                self?.logger.info("Open shortcut received")
                self?.showPopover()
            },
            onImport: { [weak self] in self?.importAndShow() }
        )
        self.shortcuts = shortcuts
        let controller = NSHostingController(rootView: MenuBarView(shortcuts: shortcuts).environmentObject(model))
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        // A transient popover may close when activation changes at the same
        // time as a global shortcut, which is easy to reproduce from a
        // fullscreen Space. Application-defined behavior leaves that lifetime
        // decision to us, so the panel remains open until an explicit close.
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.delegate = self
        installPopoverEventMonitors()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "character.bubble.fill", accessibilityDescription: "Translate Bar")
        item.button?.image?.isTemplate = true
        item.button?.toolTip = "Translate Bar"
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        statusItem = item
        showPopover()
    }

    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil) } else { showPopover() }
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        if let window = popover.contentViewController?.view.window {
            // The status item remains visible above a fullscreen Space. Tell
            // the popover window that it is an auxiliary fullscreen surface;
            // otherwise AppKit can order it into the previous Space while the
            // hotkey's originating app finishes its event.
            window.collectionBehavior.insert(.fullScreenAuxiliary)
            window.hidesOnDeactivate = false
            // Configure the window before activation so a fullscreen Space
            // can keep it as an auxiliary surface during the transition.
            if !NSApp.isActive {
                NSApp.activate(ignoringOtherApps: true)
            }
            window.makeKey()
        }
        model.requestInputFocus()
        logger.info("Popover presented: \(self.popover.isShown, privacy: .public)")
    }

    private func importAndShow() {
        logger.info("Import shortcut received")
        // Capture before activation so AX refers to the app the person was using.
        let text = SelectedTextReader.readSelectedOrClipboard()
        showPopover()
        if let text, !text.isEmpty {
            model.replaceTextFromShortcut(text)
        } else {
            model.errorMessage = "Não há texto selecionado ou copiado para traduzir."
        }
    }

    func popoverDidClose(_ notification: Notification) {
        logger.info("Popover closed")
        NotificationCenter.default.post(name: Notification.Name("TranslateBar.popoverClosed"), object: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        removePopoverEventMonitors()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return true
    }

    private func installPopoverEventMonitors() {
        guard outsideEventMonitor == nil, localEscapeMonitor == nil else { return }

        outsideEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            // A global monitor runs on AppKit's event thread. Hop back to the
            // main actor before touching the popover.
            Task { @MainActor [weak self] in
                guard let self, self.popover.isShown else { return }
                self.popover.performClose(nil)
            }
        }

        // ShortcutRecorder installs its own local monitor while capturing a
        // new combination. Let that recorder consume Escape first; otherwise
        // the popover would close before the recorder can cancel cleanly.
        localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event } // kVK_Escape
            guard let self, self.popover.isShown else { return event }
            guard self.shortcuts?.isSuspended != true else { return event }
            self.popover.performClose(nil)
            return nil
        }
    }

    private func removePopoverEventMonitors() {
        if let outsideEventMonitor {
            NSEvent.removeMonitor(outsideEventMonitor)
            self.outsideEventMonitor = nil
        }
        if let localEscapeMonitor {
            NSEvent.removeMonitor(localEscapeMonitor)
            self.localEscapeMonitor = nil
        }
    }
}
