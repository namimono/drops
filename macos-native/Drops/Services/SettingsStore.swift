import Foundation

/// Persists user-facing preferences (retention, display mode, language).
final class SettingsStore {
    static let retentionDaysKey = "drops.retentionDays"
    static let displayModeKey = "drops.shelfDisplayMode"
    static let languageOverrideKey = "drops.languageOverride"

    /// `system` follows macOS; otherwise an explicit BCP-47 code (`en`, `zh-Hans`).
    enum LanguageOverride: String, Codable, Sendable, Equatable, CaseIterable {
        case system
        case english = "en"
        case simplifiedChinese = "zh-Hans"
    }

    private let defaults: UserDefaults
    private(set) var retentionDays: Int
    private(set) var displayMode: ShelfDisplayMode
    private(set) var languageOverride: LanguageOverride

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
}
