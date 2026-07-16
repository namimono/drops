import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Persists user-facing preferences (retention, display, language, shake, shortcuts).
final class SettingsStore {
    static let retentionDaysKey = "drops.retentionDays"
    static let displayModeKey = "drops.shelfDisplayMode"
    static let languageOverrideKey = "drops.languageOverride"
    static let shakeSensitivityKey = "drops.shakeSensitivity"

    /// Legacy Flutter / early-native keys kept for migration & `GlobalHotkeyManager` compat.
    static let legacyHotkeyEnabledKey = "globalHotkeyEnabled"
    static let legacyHotkeyKeyCodeKey = "globalHotkeyKeyCode"
    static let legacyHotkeyModifiersKey = "globalHotkeyModifiers"

    static let hotkeyEnabledKey = "drops.globalHotkeyEnabled"
    static let hotkeyKeyCodeKey = "drops.globalHotkeyKeyCode"
    static let hotkeyModifiersKey = "drops.globalHotkeyModifiers"

    static let menuNewShelfKeyCodeKey = "drops.shortcut.newShelf.keyCode"
    static let menuNewShelfModifiersKey = "drops.shortcut.newShelf.modifiers"
    static let menuSettingsKeyCodeKey = "drops.shortcut.settings.keyCode"
    static let menuSettingsModifiersKey = "drops.shortcut.settings.modifiers"
    static let menuCloseAllKeyCodeKey = "drops.shortcut.closeAll.keyCode"
    static let menuCloseAllModifiersKey = "drops.shortcut.closeAll.modifiers"
    static let menuQuitKeyCodeKey = "drops.shortcut.quit.keyCode"
    static let menuQuitModifiersKey = "drops.shortcut.quit.modifiers"

    /// `system` follows macOS; otherwise an explicit BCP-47 code (`en`, `zh-Hans`).
    enum LanguageOverride: String, Codable, Sendable, Equatable, CaseIterable {
        case system
        case english = "en"
        case simplifiedChinese = "zh-Hans"
    }

    /// How easily drag-shake summons a transient shelf. Medium matches historical defaults.
    enum ShakeSensitivity: String, Codable, Sendable, Equatable, CaseIterable {
        case low
        case medium
        case high

        var threshold: Int {
            switch self {
            case .high: return 3
            case .medium: return 4
            case .low: return 6
            }
        }

        var minVelocity: CGFloat {
            switch self {
            case .high: return 140
            case .medium: return 200
            case .low: return 320
            }
        }

        var timeWindow: TimeInterval {
            switch self {
            case .high: return 1.2
            case .medium: return 1.0
            case .low: return 0.85
            }
        }
    }

    /// Configurable actions shown in Settings → Shortcuts.
    enum ShortcutAction: String, CaseIterable, Identifiable, Hashable, Sendable {
        case summonShelf
        case newShelf
        case openSettings
        case closeAll
        case quit

        var id: String { rawValue }

        var isGlobal: Bool { self == .summonShelf }

        var defaultChord: ShortcutChord {
            switch self {
            case .summonShelf:
                return ShortcutChord(
                    keyCode: GlobalHotkeyManager.defaultKeyCode,
                    carbonModifiers: GlobalHotkeyManager.defaultModifiers
                )
            case .newShelf:
                return ShortcutChord(keyCode: 45, carbonModifiers: UInt32(cmdKey)) // N
            case .openSettings:
                return ShortcutChord(keyCode: 43, carbonModifiers: UInt32(cmdKey)) // ,
            case .closeAll:
                return ShortcutChord(keyCode: 13, carbonModifiers: UInt32(cmdKey)) // W
            case .quit:
                return ShortcutChord(keyCode: 12, carbonModifiers: UInt32(cmdKey)) // Q
            }
        }
    }

    private let defaults: UserDefaults
    private(set) var retentionDays: Int
    private(set) var displayMode: ShelfDisplayMode
    private(set) var languageOverride: LanguageOverride
    private(set) var shakeSensitivity: ShakeSensitivity
    private(set) var globalHotkeyEnabled: Bool
    private(set) var globalHotkey: ShortcutChord
    private(set) var menuNewShelf: ShortcutChord
    private(set) var menuOpenSettings: ShortcutChord
    private(set) var menuCloseAll: ShortcutChord
    private(set) var menuQuit: ShortcutChord

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.object(forKey: Self.retentionDaysKey) as? Int
        if let stored, (try? RetentionPolicy(days: stored)) != nil {
            retentionDays = stored
        } else {
            retentionDays = RetentionPolicy.defaultDays
        }

        if let raw = defaults.string(forKey: Self.displayModeKey),
           let mode = ShelfDisplayMode(rawValue: raw) {
            displayMode = mode
        } else {
            displayMode = .grid
        }

        if let raw = defaults.string(forKey: Self.languageOverrideKey),
           let language = LanguageOverride(rawValue: raw) {
            languageOverride = language
        } else {
            languageOverride = .system
        }

        if let raw = defaults.string(forKey: Self.shakeSensitivityKey),
           let sensitivity = ShakeSensitivity(rawValue: raw) {
            shakeSensitivity = sensitivity
        } else {
            shakeSensitivity = .medium
        }

        globalHotkeyEnabled = Self.bool(
            defaults,
            keys: [Self.hotkeyEnabledKey, Self.legacyHotkeyEnabledKey],
            fallback: true
        )
        globalHotkey = Self.loadChord(
            defaults,
            keyCodeKeys: [Self.hotkeyKeyCodeKey, Self.legacyHotkeyKeyCodeKey],
            modifierKeys: [Self.hotkeyModifiersKey, Self.legacyHotkeyModifiersKey],
            fallback: ShortcutAction.summonShelf.defaultChord
        )
        menuNewShelf = Self.loadChord(
            defaults,
            keyCodeKeys: [Self.menuNewShelfKeyCodeKey],
            modifierKeys: [Self.menuNewShelfModifiersKey],
            fallback: ShortcutAction.newShelf.defaultChord
        )
        menuOpenSettings = Self.loadChord(
            defaults,
            keyCodeKeys: [Self.menuSettingsKeyCodeKey],
            modifierKeys: [Self.menuSettingsModifiersKey],
            fallback: ShortcutAction.openSettings.defaultChord
        )
        menuCloseAll = Self.loadChord(
            defaults,
            keyCodeKeys: [Self.menuCloseAllKeyCodeKey],
            modifierKeys: [Self.menuCloseAllModifiersKey],
            fallback: ShortcutAction.closeAll.defaultChord
        )
        menuQuit = Self.loadChord(
            defaults,
            keyCodeKeys: [Self.menuQuitKeyCodeKey],
            modifierKeys: [Self.menuQuitModifiersKey],
            fallback: ShortcutAction.quit.defaultChord
        )
    }

    /// Accepts only 1...120. Illegal input leaves the previous valid value unchanged.
    @discardableResult
    func setRetentionDays(_ days: Int) throws -> Int {
        let policy = try RetentionPolicy(days: days)
        retentionDays = policy.days
        defaults.set(retentionDays, forKey: Self.retentionDaysKey)
        return retentionDays
    }

    func setDisplayMode(_ mode: ShelfDisplayMode) {
        displayMode = mode
        defaults.set(mode.rawValue, forKey: Self.displayModeKey)
    }

    func setLanguageOverride(_ language: LanguageOverride) {
        languageOverride = language
        defaults.set(language.rawValue, forKey: Self.languageOverrideKey)
    }

    func setShakeSensitivity(_ sensitivity: ShakeSensitivity) {
        shakeSensitivity = sensitivity
        defaults.set(sensitivity.rawValue, forKey: Self.shakeSensitivityKey)
    }

    func setGlobalHotkeyEnabled(_ enabled: Bool) {
        globalHotkeyEnabled = enabled
        defaults.set(enabled, forKey: Self.hotkeyEnabledKey)
        defaults.set(enabled, forKey: Self.legacyHotkeyEnabledKey)
    }

    @discardableResult
    func setShortcut(_ action: ShortcutAction, chord: ShortcutChord) -> Bool {
        guard chord.carbonModifiers != 0 else { return false }
        guard ShortcutChord.menuKeyEquivalent(for: chord.keyCode) != nil || action.isGlobal else {
            return false
        }
        if conflictingAction(with: chord, excluding: action) != nil {
            return false
        }

        switch action {
        case .summonShelf:
            globalHotkey = chord
            defaults.set(Int(chord.keyCode), forKey: Self.hotkeyKeyCodeKey)
            defaults.set(Int(chord.carbonModifiers), forKey: Self.hotkeyModifiersKey)
            defaults.set(Int(chord.keyCode), forKey: Self.legacyHotkeyKeyCodeKey)
            defaults.set(Int(chord.carbonModifiers), forKey: Self.legacyHotkeyModifiersKey)
        case .newShelf:
            menuNewShelf = chord
            persist(chord, keyCodeKey: Self.menuNewShelfKeyCodeKey, modifiersKey: Self.menuNewShelfModifiersKey)
        case .openSettings:
            menuOpenSettings = chord
            persist(chord, keyCodeKey: Self.menuSettingsKeyCodeKey, modifiersKey: Self.menuSettingsModifiersKey)
        case .closeAll:
            menuCloseAll = chord
            persist(chord, keyCodeKey: Self.menuCloseAllKeyCodeKey, modifiersKey: Self.menuCloseAllModifiersKey)
        case .quit:
            menuQuit = chord
            persist(chord, keyCodeKey: Self.menuQuitKeyCodeKey, modifiersKey: Self.menuQuitModifiersKey)
        }
        return true
    }

    func resetShortcut(_ action: ShortcutAction) {
        _ = setShortcut(action, chord: action.defaultChord)
    }

    func resetAllShortcuts() {
        setGlobalHotkeyEnabled(true)
        for action in ShortcutAction.allCases {
            resetShortcut(action)
        }
    }

    func chordFor(_ action: ShortcutAction) -> ShortcutChord {
        switch action {
        case .summonShelf: return globalHotkey
        case .newShelf: return menuNewShelf
        case .openSettings: return menuOpenSettings
        case .closeAll: return menuCloseAll
        case .quit: return menuQuit
        }
    }

    func menuShortcutBindings() -> MenuShortcutBindings {
        MenuShortcutBindings(
            newShelf: menuNewShelf,
            openSettings: menuOpenSettings,
            closeAll: menuCloseAll,
            quit: menuQuit
        )
    }

    // MARK: - Private

    private func persist(_ chord: ShortcutChord, keyCodeKey: String, modifiersKey: String) {
        defaults.set(Int(chord.keyCode), forKey: keyCodeKey)
        defaults.set(Int(chord.carbonModifiers), forKey: modifiersKey)
    }

    private func conflictingAction(
        with candidate: ShortcutChord,
        excluding: ShortcutAction
    ) -> ShortcutAction? {
        for action in ShortcutAction.allCases where action != excluding {
            if chordFor(action) == candidate { return action }
        }
        return nil
    }

    private static func bool(_ defaults: UserDefaults, keys: [String], fallback: Bool) -> Bool {
        for key in keys {
            if let value = defaults.object(forKey: key) as? Bool { return value }
            if let number = defaults.object(forKey: key) as? NSNumber { return number.boolValue }
        }
        return fallback
    }

    private static func loadChord(
        _ defaults: UserDefaults,
        keyCodeKeys: [String],
        modifierKeys: [String],
        fallback: ShortcutChord
    ) -> ShortcutChord {
        let keyCode = int(defaults, keys: keyCodeKeys, fallback: Int(fallback.keyCode))
        let modifiers = int(defaults, keys: modifierKeys, fallback: Int(fallback.carbonModifiers))
        return ShortcutChord(keyCode: UInt32(keyCode), carbonModifiers: UInt32(modifiers))
    }

    private static func int(_ defaults: UserDefaults, keys: [String], fallback: Int) -> Int {
        for key in keys {
            if let value = defaults.object(forKey: key) as? Int { return value }
            if let number = defaults.object(forKey: key) as? NSNumber { return number.intValue }
        }
        return fallback
    }
}

/// Carbon-style key chord used for global hotkeys and menu key equivalents.
struct ShortcutChord: Equatable, Sendable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    var displayString: String {
        GlobalHotkeyManager.displayString(keyCode: keyCode, modifiers: carbonModifiers)
    }

    var nsModifierFlags: NSEvent.ModifierFlags {
        GlobalHotkeyManager.modifierFlags(from: carbonModifiers)
    }

    /// Character for `NSMenuItem.keyEquivalent`, if representable.
    var menuKeyEquivalent: String? {
        Self.menuKeyEquivalent(for: keyCode)
    }

    static func menuKeyEquivalent(for keyCode: UInt32) -> String? {
        let names: [UInt32: String] = [
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z",
            7: "x", 8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e",
            15: "r", 16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4",
            22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
            29: "0", 30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p",
            37: "l", 38: "j", 39: "'", 40: "k", 41: ";", 42: "\\",
            43: ",", 44: "/", 45: "n", 46: "m", 47: ".",
            49: " ",
        ]
        return names[keyCode]
    }
}

struct MenuShortcutBindings: Equatable, Sendable {
    var newShelf: ShortcutChord
    var openSettings: ShortcutChord
    var closeAll: ShortcutChord
    var quit: ShortcutChord
}
