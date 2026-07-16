import Carbon.HIToolbox
import XCTest
@testable import Drops

final class SettingsStoreTests: XCTestCase {
    func testRejectsInvalidRetentionAndKeepsPrevious() throws {
        let suite = "click.shakepin.macos.tests.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.retentionDays, 30)

        XCTAssertEqual(try settings.setRetentionDays(45), 45)
        XCTAssertEqual(settings.retentionDays, 45)

        XCTAssertThrowsError(try settings.setRetentionDays(0))
        XCTAssertThrowsError(try settings.setRetentionDays(121))
        XCTAssertEqual(settings.retentionDays, 45, "Illegal input must not overwrite last valid value")
    }

    func testDisplayModeAndLanguagePersist() {
        let suite = "click.shakepin.macos.tests.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.displayMode, .grid)
        XCTAssertEqual(settings.languageOverride, .system)

        settings.setDisplayMode(.list)
        settings.setLanguageOverride(.simplifiedChinese)

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.displayMode, .list)
        XCTAssertEqual(reloaded.languageOverride, .simplifiedChinese)
    }

    func testShakeSensitivityPersistsAndMapsParameters() {
        let suite = "click.shakepin.macos.tests.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.shakeSensitivity, .medium)
        XCTAssertEqual(settings.shakeSensitivity.threshold, 4)
        XCTAssertEqual(settings.shakeSensitivity.minVelocity, 200)

        settings.setShakeSensitivity(.high)
        XCTAssertEqual(SettingsStore(defaults: defaults).shakeSensitivity, .high)
        XCTAssertEqual(SettingsStore.ShakeSensitivity.high.threshold, 3)
        XCTAssertLessThan(
            SettingsStore.ShakeSensitivity.high.minVelocity,
            SettingsStore.ShakeSensitivity.medium.minVelocity
        )

        settings.setShakeSensitivity(.low)
        XCTAssertEqual(SettingsStore(defaults: defaults).shakeSensitivity, .low)
        XCTAssertGreaterThan(
            SettingsStore.ShakeSensitivity.low.threshold,
            SettingsStore.ShakeSensitivity.medium.threshold
        )
    }

    func testShortcutsPersistRejectConflictsAndReset() {
        let suite = "click.shakepin.macos.tests.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = SettingsStore(defaults: defaults)
        XCTAssertTrue(settings.globalHotkeyEnabled)
        XCTAssertEqual(
            settings.globalHotkey.displayString,
            SettingsStore.ShortcutAction.summonShelf.defaultChord.displayString
        )

        let custom = ShortcutChord(keyCode: 49, carbonModifiers: UInt32(cmdKey | shiftKey)) // ⌘⇧Space
        XCTAssertTrue(settings.setShortcut(.summonShelf, chord: custom))
        XCTAssertEqual(SettingsStore(defaults: defaults).globalHotkey, custom)

        settings.setGlobalHotkeyEnabled(false)
        XCTAssertFalse(SettingsStore(defaults: defaults).globalHotkeyEnabled)

        // Conflict with summon shelf
        XCTAssertFalse(settings.setShortcut(.newShelf, chord: custom))
        XCTAssertEqual(settings.menuNewShelf, SettingsStore.ShortcutAction.newShelf.defaultChord)

        // No modifiers rejected
        XCTAssertFalse(
            settings.setShortcut(.closeAll, chord: ShortcutChord(keyCode: 13, carbonModifiers: 0))
        )

        settings.resetShortcut(.summonShelf)
        XCTAssertEqual(
            settings.globalHotkey,
            SettingsStore.ShortcutAction.summonShelf.defaultChord
        )

        _ = settings.setShortcut(
            .quit,
            chord: ShortcutChord(keyCode: 12, carbonModifiers: UInt32(cmdKey | optionKey))
        )
        settings.resetAllShortcuts()
        XCTAssertTrue(settings.globalHotkeyEnabled)
        XCTAssertEqual(settings.menuQuit, SettingsStore.ShortcutAction.quit.defaultChord)
    }

    func testMigratesLegacyGlobalHotkeyKeys() {
        let suite = "click.shakepin.macos.tests.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(false, forKey: SettingsStore.legacyHotkeyEnabledKey)
        defaults.set(8, forKey: SettingsStore.legacyHotkeyKeyCodeKey) // C
        defaults.set(Int(cmdKey | optionKey), forKey: SettingsStore.legacyHotkeyModifiersKey)

        let settings = SettingsStore(defaults: defaults)
        XCTAssertFalse(settings.globalHotkeyEnabled)
        XCTAssertEqual(settings.globalHotkey.keyCode, 8)
        XCTAssertEqual(settings.globalHotkey.carbonModifiers, UInt32(cmdKey | optionKey))
    }
}
