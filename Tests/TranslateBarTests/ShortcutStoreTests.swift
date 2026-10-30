import XCTest
import AppKit
@testable import TranslateBarKit

@MainActor
final class ShortcutStoreTests: XCTestCase {
    func testDefaultsUseSeparateUsefulShortcuts() {
        XCTAssertNotEqual(ShortcutDefinition.openDefault, ShortcutDefinition.importDefault)
        XCTAssertEqual(ShortcutDefinition.openDefault.displayName, "⇧⌘Espaço")
        XCTAssertEqual(ShortcutDefinition.importDefault.displayName, "⌃⌥V")
    }

    func testShortcutDefinitionsPersistWithoutRegisteringGlobalEvents() throws {
        let suiteName = "TranslateBar.ShortcutStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = ShortcutStore(defaults: defaults, registerImmediately: false)
        first.openShortcut = ShortcutDefinition(keyCode: 0, modifiers: 0x1000)
        first.importShortcut = ShortcutDefinition(keyCode: 9, modifiers: 0x800)

        let second = ShortcutStore(defaults: defaults, registerImmediately: false)
        XCTAssertEqual(second.openShortcut, first.openShortcut)
        XCTAssertEqual(second.importShortcut, first.importShortcut)
    }

    func testShortcutEnabledFlagsPersistAndDefaultsStayEnabled() throws {
        let suiteName = "TranslateBar.ShortcutStoreTests.Enabled.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = ShortcutStore(defaults: defaults, registerImmediately: false)
        XCTAssertTrue(first.openShortcutEnabled)
        XCTAssertTrue(first.importShortcutEnabled)
        first.openShortcutEnabled = false
        first.importShortcutEnabled = false

        let second = ShortcutStore(defaults: defaults, registerImmediately: false)
        XCTAssertFalse(second.openShortcutEnabled)
        XCTAssertFalse(second.importShortcutEnabled)

        // Re-enabling only one action must not affect the other one.
        second.importShortcutEnabled = true
        XCTAssertFalse(second.openShortcutEnabled)
        XCTAssertTrue(second.importShortcutEnabled)
    }

    func testLegacyShortcutSettingsMigrateWithBothActionsEnabled() throws {
        let suiteName = "TranslateBar.ShortcutStoreTests.Legacy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacy: [String: ShortcutDefinition] = [
            "open": ShortcutDefinition(keyCode: 0, modifiers: 0x1000),
            "import": ShortcutDefinition(keyCode: 9, modifiers: 0x800)
        ]
        defaults.set(try JSONEncoder().encode(legacy), forKey: "translateBar.shortcuts.v1")
        defaults.removeObject(forKey: "translateBar.shortcuts.openEnabled.v1")
        defaults.removeObject(forKey: "translateBar.shortcuts.importEnabled.v1")

        let migrated = ShortcutStore(defaults: defaults, registerImmediately: false)
        XCTAssertEqual(migrated.openShortcut.keyCode, 0)
        XCTAssertEqual(migrated.importShortcut.keyCode, 9)
        XCTAssertTrue(migrated.openShortcutEnabled)
        XCTAssertTrue(migrated.importShortcutEnabled)
    }

    func testRecorderRejectsShiftOnlyButAcceptsUsefulModifier() throws {
        let shiftOnly = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: 0
        ))
        XCTAssertNil(ShortcutDefinition(event: shiftOnly))

        let commandShortcut = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: 0
        ))
        let captured = try XCTUnwrap(ShortcutDefinition(event: commandShortcut))
        XCTAssertTrue(captured.modifierFlags.contains(.command))
        XCTAssertTrue(captured.modifierFlags.contains(.shift))
    }
}
