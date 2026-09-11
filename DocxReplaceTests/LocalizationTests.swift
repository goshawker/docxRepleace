import XCTest
@testable import DocxReplace

@MainActor
final class LocalizationTests: XCTestCase {
    // MARK: - 系统语言解析

    func testResolveFollowsSystemChinese() {
        XCTAssertEqual(AppLanguage.resolve(.system, preferred: ["zh-Hans-CN", "en-US"]), .zhHans)
    }

    func testResolveFollowsSystemEnglish() {
        XCTAssertEqual(AppLanguage.resolve(.system, preferred: ["en-US"]), .en)
    }

    func testResolveFallsBackToEnglishForUnknownLanguage() {
        XCTAssertEqual(AppLanguage.resolve(.system, preferred: ["fr-FR"]), .en)
    }

    func testResolveFallsBackToEnglishForEmptyPreferenceList() {
        XCTAssertEqual(AppLanguage.resolve(.system, preferred: []), .en)
    }

    func testExplicitLanguageIgnoresPreferenceList() {
        XCTAssertEqual(AppLanguage.resolve(.zhHans, preferred: ["en-US"]), .zhHans)
        XCTAssertEqual(AppLanguage.resolve(.en, preferred: ["zh-Hans-CN"]), .en)
    }

    // MARK: - 状态对象按当前语言取词表

    func testStringsTableMatchesEffectiveLanguage() {
        let saved = Localization.shared.language
        defer { Localization.shared.language = saved }

        Localization.shared.language = .zhHans
        XCTAssertTrue(Localization.shared.strings is ChineseStrings)

        Localization.shared.language = .en
        XCTAssertTrue(Localization.shared.strings is EnglishStrings)
    }

    func testSavedLanguageIsPersistedAndReloaded() {
        let saved = Localization.shared.language
        defer { Localization.shared.language = saved }

        Localization.shared.language = .en
        XCTAssertEqual(UserDefaults.standard.string(forKey: "appLanguage"), "en")
    }

    // MARK: - 词表内容抽查

    func testKeyEntriesDifferBetweenTables() {
        let zh = ChineseStrings()
        let en = EnglishStrings()

        XCTAssertNotEqual(zh.appTitle, en.appTitle)
        XCTAssertNotEqual(zh.scanButton, en.scanButton)
        XCTAssertNotEqual(zh.statusNoMatch, en.statusNoMatch)
        XCTAssertNotEqual(zh.matchCount(1), en.matchCount(1))
        XCTAssertNotEqual(zh.zipNotAFile, en.zipNotAFile)
    }

    func testKeyEntriesAreNonEmptyInBothTables() {
        let zh = ChineseStrings()
        let en = EnglishStrings()

        for table in [zh as AppStrings, en as AppStrings] {
            XCTAssertFalse(table.appTitle.isEmpty)
            XCTAssertFalse(table.scanButton.isEmpty)
            XCTAssertFalse(table.statusNoMatch.isEmpty)
            XCTAssertFalse(table.fileNotWritable.isEmpty)
            XCTAssertFalse(table.legacyDocument.isEmpty)
            XCTAssertFalse(table.matchCount(0).isEmpty)
            XCTAssertFalse(table.partMessage(part: "word/document.xml", message: "x").isEmpty)
        }
    }

    // MARK: - Core 错误文案随之本地化

    func testCoreErrorMessagesUseTheGivenTable() {
        let zh = ZipError.notAZipFile.message(ChineseStrings())
        let en = ZipError.notAZipFile.message(EnglishStrings())
        XCTAssertNotEqual(zh, en)
        XCTAssertTrue(zh.contains("docx"))
        XCTAssertTrue(en.contains("docx"))

        XCTAssertNotEqual(DocxXmlError.parseFailed("x").message(ChineseStrings()),
                          DocxXmlError.parseFailed("x").message(EnglishStrings()))
    }

    func testCoordinatorDefaultStringsStayChinese() {
        // 旧调用点不传 strings 时必须与改造前行为一致（既有测试依赖这个默认值）
        XCTAssertEqual(ReplaceCoordinator.describe(ZipError.notAZipFile, ChineseStrings()),
                       "不是有效的 .docx 文件（可能是 .doc 或已损坏）")
    }
}
