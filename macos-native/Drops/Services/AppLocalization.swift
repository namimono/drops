import Foundation

extension Notification.Name {
    static let dropsLanguageDidChange = Notification.Name("drops.languageDidChange")
}

/// Resolves effective UI language and looks up String Catalog entries without requiring a relaunch.
enum AppLocalization {
    private static let lock = NSLock()
    private static var _override: SettingsStore.LanguageOverride = .system

    static var languageOverride: SettingsStore.LanguageOverride {
        get {
            lock.lock(); defer { lock.unlock() }
            return _override
        }
        set {
            lock.lock()
            _override = newValue
            lock.unlock()
            applyAppleLanguages(newValue)
            NotificationCenter.default.post(name: .dropsLanguageDidChange, object: nil)
        }
    }

    /// `en` or `zh-Hans`. Unsupported system languages fall back to English (S3-11).
    static var effectiveLanguageCode: String {
        switch languageOverride {
        case .english:
            return "en"
        case .simplifiedChinese:
            return "zh-Hans"
        case .system:
            return systemResolvedLanguageCode()
        }
    }

    static func applyStoredOverride(_ override: SettingsStore.LanguageOverride) {
        lock.lock()
        _override = override
        lock.unlock()
        applyAppleLanguages(override)
    }

    static func string(_ key: String, defaultValue: String? = nil) -> String {
        let fallback = defaultValue ?? key
        let language = effectiveLanguageCode
        if let bundle = localizationBundle(for: language) {
            let value = bundle.localizedString(forKey: key, value: "\u{0}", table: "Localizable")
            if value != "\u{0}" { return value }
        }
        let main = Bundle.main.localizedString(forKey: key, value: "\u{0}", table: "Localizable")
        if main != "\u{0}" { return main }
        return fallback
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        let template = string(key)
        return String(format: template, locale: Locale(identifier: effectiveLanguageCode), arguments: arguments)
    }

    // MARK: - Private

    private static func systemResolvedLanguageCode() -> String {
        for preferred in Locale.preferredLanguages {
            if isSimplifiedChinese(preferred) { return "zh-Hans" }
            if preferred.hasPrefix("en") { return "en" }
        }
        return "en"
    }

    private static func isSimplifiedChinese(_ identifier: String) -> Bool {
        let lower = identifier.lowercased()
        if lower.hasPrefix("zh-hans") || lower.hasPrefix("zh-cn") { return true }
        if lower == "zh" { return true }
        if lower.hasPrefix("zh-") && lower.contains("hans") { return true }
        return false
    }

    private static func localizationBundle(for language: String) -> Bundle? {
        if let path = Bundle.main.path(forResource: language, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return nil
    }

    private static func applyAppleLanguages(_ override: SettingsStore.LanguageOverride) {
        switch override {
        case .system:
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        case .english:
            UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        case .simplifiedChinese:
            UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
        }
    }
}

/// Typed keys for String Catalog entries.
enum L10n {
    static var appName: String { AppLocalization.string("app.name") }
    static var newShelf: String { AppLocalization.string("menu.new_shelf") }
    static var settings: String { AppLocalization.string("menu.settings") }
    static var about: String { AppLocalization.string("menu.about") }
    static var showLogs: String { AppLocalization.string("menu.show_logs") }
    static var cleanTemporary: String { AppLocalization.string("menu.clean_temporary") }
    static var closeAllShelves: String { AppLocalization.string("menu.close_all") }
    static var quit: String { AppLocalization.string("menu.quit") }
    static var newTransientDemo: String { AppLocalization.string("menu.new_transient_demo") }
    static var createThreeShelves: String { AppLocalization.string("menu.create_three") }
    static var logBenchmarks: String { AppLocalization.string("menu.log_benchmarks") }

    static var expand: String { AppLocalization.string("shelf.expand") }
    static var collapse: String { AppLocalization.string("shelf.collapse") }
    static var close: String { AppLocalization.string("shelf.close") }
    static var grid: String { AppLocalization.string("shelf.grid") }
    static var list: String { AppLocalization.string("shelf.list") }
    static var dragAll: String { AppLocalization.string("shelf.drag_all") }
    static var emptyDrop: String { AppLocalization.string("shelf.empty_prompt") }
    static var itemMenu: String { AppLocalization.string("shelf.item_menu") }
    static var open: String { AppLocalization.string("shelf.open") }
    static var revealInFinder: String { AppLocalization.string("shelf.reveal") }
    static var mergeText: String { AppLocalization.string("shelf.merge_text") }
    static var mergeHoverPending: String { AppLocalization.string("shelf.merge_hover_pending") }
    static var mergeHoverArmed: String { AppLocalization.string("shelf.merge_hover_armed") }
    static var remove: String { AppLocalization.string("shelf.remove") }

    static func shelfTitle(shortID: String) -> String {
        AppLocalization.format("shelf.title_format", shortID)
    }

    static func shelfStatus(lifecycle: String, presentation: String, count: Int) -> String {
        AppLocalization.format("shelf.status_format", lifecycle, presentation, count)
    }

    static func collapsedStackSummary(count: Int) -> String {
        AppLocalization.format("shelf.collapsed_summary", count)
    }

    static var settingsWindowTitle: String { AppLocalization.string("settings.window_title") }
    static var settingsGeneral: String { AppLocalization.string("settings.general") }
    static var settingsInteraction: String { AppLocalization.string("settings.interaction") }
    static var settingsShortcuts: String { AppLocalization.string("settings.shortcuts") }
    static var settingsRetention: String { AppLocalization.string("settings.retention") }
    static var settingsSave: String { AppLocalization.string("settings.save") }
    static var settingsRetentionError: String { AppLocalization.string("settings.retention_error") }
    static var settingsDefaultView: String { AppLocalization.string("settings.default_view") }
    static var settingsLanguage: String { AppLocalization.string("settings.language") }
    static var settingsLanguageSystem: String { AppLocalization.string("settings.language_system") }
    static var settingsLanguageEnglish: String { AppLocalization.string("settings.language_english") }
    static var settingsLanguageChinese: String { AppLocalization.string("settings.language_chinese") }
    static var settingsMaintenance: String { AppLocalization.string("settings.maintenance") }
    static var settingsCleanupHint: String { AppLocalization.string("settings.cleanup_hint") }
    static var settingsSecurity: String { AppLocalization.string("settings.security") }
    static var settingsSecurityBody: String { AppLocalization.string("settings.security_body") }
    static var settingsLanguageRestartHint: String { AppLocalization.string("settings.language_restart_hint") }
    static var settingsShakeSensitivity: String { AppLocalization.string("settings.shake_sensitivity") }
    static var settingsShakeLow: String { AppLocalization.string("settings.shake_low") }
    static var settingsShakeMedium: String { AppLocalization.string("settings.shake_medium") }
    static var settingsShakeHigh: String { AppLocalization.string("settings.shake_high") }
    static var settingsShakeHint: String { AppLocalization.string("settings.shake_hint") }
    static var settingsHotkeyEnabled: String { AppLocalization.string("settings.hotkey_enabled") }
    static var settingsHotkeySummon: String { AppLocalization.string("settings.hotkey_summon") }
    static var settingsHotkeyGlobalCaption: String { AppLocalization.string("settings.hotkey_global_caption") }
    static var settingsHotkeyHint: String { AppLocalization.string("settings.hotkey_hint") }
    static var settingsHotkeyRecording: String { AppLocalization.string("settings.hotkey_recording") }
    static var settingsHotkeyConflict: String { AppLocalization.string("settings.hotkey_conflict") }
    static var settingsResetShortcut: String { AppLocalization.string("settings.reset_shortcut") }
    static var settingsResetAllShortcuts: String { AppLocalization.string("settings.reset_all_shortcuts") }

    static var aboutWindowTitle: String { AppLocalization.string("about.window_title") }
    static var aboutBlurb: String { AppLocalization.string("about.blurb") }
    static func aboutVersion(_ version: String, _ build: String) -> String {
        AppLocalization.format("about.version_format", version, build)
    }

    static var cleanConfirmTitle: String { AppLocalization.string("alert.clean_title") }
    static var cleanConfirmBody: String { AppLocalization.string("alert.clean_body") }
    static var cleanNow: String { AppLocalization.string("alert.clean_now") }
    static var cancel: String { AppLocalization.string("alert.cancel") }
    static var ok: String { AppLocalization.string("alert.ok") }
    static var cleanResultTitle: String { AppLocalization.string("alert.clean_result_title") }
    static func cleanResultBody(deleted: Int, skipped: Int) -> String {
        AppLocalization.format("alert.clean_result_body", deleted, skipped)
    }
    static var cleanupFailed: String { AppLocalization.string("alert.cleanup_failed") }
    static var retentionUpdated: String { AppLocalization.string("alert.retention_updated") }
    static func retentionUpdatedBody(_ days: Int) -> String {
        AppLocalization.format("alert.retention_updated_body", days)
    }
    static var invalidRetention: String { AppLocalization.string("alert.invalid_retention") }
    static func invalidRetentionBody(_ current: Int) -> String {
        AppLocalization.format("alert.invalid_retention_body", current)
    }
    static var logsUnavailable: String { AppLocalization.string("alert.logs_unavailable") }
    static var logsUnavailableBody: String { AppLocalization.string("alert.logs_unavailable_body") }
    static var unableToOpen: String { AppLocalization.string("alert.unable_to_open") }
    static var unableToReveal: String { AppLocalization.string("alert.unable_to_reveal") }
    static func couldNotOpen(_ name: String) -> String {
        AppLocalization.format("alert.could_not_open", name)
    }
    static func couldNotReveal(_ name: String) -> String {
        AppLocalization.format("alert.could_not_reveal", name)
    }
    static var revealNeedsLocal: String { AppLocalization.string("alert.reveal_needs_local") }
    static var recoveryFileMissing: String { AppLocalization.string("alert.recovery_file_missing") }
    static var recoveryNoTarget: String { AppLocalization.string("alert.recovery_no_target") }
    static var recoveryLink: String { AppLocalization.string("alert.recovery_link") }
    static var recoveryDefaultApp: String { AppLocalization.string("alert.recovery_default_app") }
    static var recoveryReveal: String { AppLocalization.string("alert.recovery_reveal") }
    static var recoveryGeneric: String { AppLocalization.string("alert.recovery_generic") }

    static var a11yStatusItem: String { AppLocalization.string("a11y.status_item") }
    static var a11yShelfWindow: String { AppLocalization.string("a11y.shelf_window") }
    static var a11yItemList: String { AppLocalization.string("a11y.item_list") }
    static var a11yItemGrid: String { AppLocalization.string("a11y.item_grid") }
    static var a11yCollapsedStack: String { AppLocalization.string("a11y.collapsed_stack") }
    static func a11yItem(_ name: String) -> String {
        AppLocalization.format("a11y.item_format", name)
    }
    static func a11yCollapsedCount(_ count: Int) -> String {
        AppLocalization.format("a11y.collapsed_count", count)
    }

    static var mergedTextFileName: String { AppLocalization.string("merge.filename") }
}
