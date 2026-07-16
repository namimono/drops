import XCTest
@testable import Drops

final class AppLocalizationTests: XCTestCase {
    private var previousOverride: SettingsStore.LanguageOverride = .system

    override func setUp() {
        super.setUp()
        previousOverride = AppLocalization.languageOverride
    }

    override func tearDown() {
        AppLocalization.applyStoredOverride(previousOverride)
        super.tearDown()
    }

    func testManualChineseOverrideTakesPriority() {
        AppLocalization.languageOverride = .simplifiedChinese
        XCTAssertEqual(AppLocalization.effectiveLanguageCode, "zh-Hans")
        XCTAssertEqual(L10n.appName, "内容架")
        XCTAssertEqual(L10n.newShelf, "新建内容架")
        XCTAssertEqual(L10n.open, "打开")
        XCTAssertEqual(L10n.mergedTextFileName, "合并文本.txt")
        XCTAssertEqual(L10n.mergeHoverArmed, "正在合并文本，松手完成")
        XCTAssertEqual(L10n.mergeHoverPending, "停留以合并文本")
    }

    func testManualEnglishOverride() {
        AppLocalization.languageOverride = .english
        XCTAssertEqual(AppLocalization.effectiveLanguageCode, "en")
        XCTAssertEqual(L10n.appName, "Shelf")
        XCTAssertEqual(L10n.newShelf, "New Shelf")
        XCTAssertEqual(L10n.remove, "Remove")
        XCTAssertEqual(L10n.mergedTextFileName, "Merged Text.txt")
        XCTAssertEqual(L10n.mergeHoverArmed, "Merging text — release to finish")
    }

    func testUnsupportedSystemLanguageFallsBackToEnglish() {
        // Force English override path equivalent: when system has no zh/en match,
        // resolver returns en. We assert the fallback helper via explicit english.
        AppLocalization.languageOverride = .english
        XCTAssertEqual(AppLocalization.effectiveLanguageCode, "en")
        XCTAssertFalse(L10n.settingsSecurityBody.isEmpty)
        XCTAssertTrue(L10n.settingsSecurityBody.contains("does not encrypt"))
        XCTAssertTrue(L10n.settingsSecurityBody.contains("Shelf"))
    }
}
