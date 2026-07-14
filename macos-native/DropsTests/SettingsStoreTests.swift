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
}
