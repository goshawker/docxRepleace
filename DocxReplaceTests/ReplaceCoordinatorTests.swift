import XCTest
@testable import DocxReplace

final class ReplaceCoordinatorTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CoordinatorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("子目录"),
                                                withIntermediateDirectories: true)
        let fm = FileManager.default
        try DocxFixture.docx(bodyXML: DocxFixture.paragraph(["北京", "公司"]))
            .write(to: root.appendingPathComponent("A.docx"))
        try DocxFixture.docx(bodyXML: DocxFixture.paragraph(["无关内容"]))
            .write(to: root.appendingPathComponent("子目录/B.docx"))
        try Data("legacy".utf8).write(to: root.appendingPathComponent("旧.doc"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testScanReportsMatchesAndSkipsLegacyDoc() async {
        let results = await ReplaceCoordinator.scan(folder: root, find: "北京公司",
                                                    options: ReplaceOptions()) { _ in }
        XCTAssertEqual(results.count, 3)
        let matched = results.filter { $0.matchCount > 0 }
        XCTAssertEqual(matched.map(\.relativePath), ["A.docx"])
        XCTAssertEqual(matched.first?.matchCount, 1)

        let legacy = results.first { $0.relativePath == "旧.doc" }
        if case .unsupported(let reason)? = legacy?.outcome {
            XCTAssertTrue(reason.contains("docx"))
        } else {
            XCTFail("过期 .doc 应标记为不支持")
        }

        let noMatch = results.first { $0.relativePath == "子目录/B.docx" }
        XCTAssertEqual(noMatch?.outcome, .noMatch)
    }

    func testScanAttachesPreviews() async {
        let results = await ReplaceCoordinator.scan(folder: root, find: "北京公司",
                                                    options: ReplaceOptions()) { _ in }
        let matched = results.first { $0.matchCount > 0 }
        XCTAssertEqual(matched?.previews.count, 1)
        XCTAssertEqual(matched?.previews.first?.match, "北京公司")
    }

    func testScanProgressReachesTotal() async {
        // 并发扫描时进度回调来自多个线程，只断言「见过的最大值」
        final class MaxTracker: @unchecked Sendable {
            private let lock = NSLock()
            private var value = 0
            func record(_ v: Int) { lock.lock(); value = max(value, v); lock.unlock() }
            var maxSeen: Int { lock.lock(); defer { lock.unlock() }; return value }
        }
        let tracker = MaxTracker()
        _ = await ReplaceCoordinator.scan(folder: root, find: "北京公司", options: ReplaceOptions()) { progress in
            tracker.record(progress.completed)
        }
        XCTAssertEqual(tracker.maxSeen, 3)
    }

    func testReplaceWritesBackupAndModifiesFile() async throws {
        let backupRoot = root.appendingPathComponent("备份")
        let results = await ReplaceCoordinator.scan(folder: root, find: "北京公司",
                                                    options: ReplaceOptions()) { _ in }
        let items = results.filter { $0.matchCount > 0 }.map(\.item)

        let report = await ReplaceCoordinator.replace(items: items, sourceFolder: root,
                                                      find: "北京公司", replaceWith: "上海集团",
                                                      options: ReplaceOptions(), backupEnabled: true,
                                                      backupRoot: backupRoot) { _ in }
        XCTAssertEqual(report.modifiedFiles, 1)
        XCTAssertEqual(report.replacedCount, 1)
        XCTAssertTrue(report.failed.isEmpty)

        let data = try Data(contentsOf: root.appendingPathComponent("A.docx"))
        XCTAssertEqual(try DocxTextReplacer.countMatches(docxData: data, find: "上海集团",
                                                         options: ReplaceOptions()), 1)

        let backupDir = try XCTUnwrap(report.backupDirectory)
        let backedUp = backupDir.appendingPathComponent("A.docx")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backedUp.path))
        XCTAssertEqual(try DocxTextReplacer.countMatches(docxData: Data(contentsOf: backedUp),
                                                         find: "北京公司", options: ReplaceOptions()), 1)
    }

    func testReplaceWithoutBackupDoesNotCreateDirectory() async throws {
        let results = await ReplaceCoordinator.scan(folder: root, find: "北京公司",
                                                    options: ReplaceOptions()) { _ in }
        let items = results.filter { $0.matchCount > 0 }.map(\.item)
        let report = await ReplaceCoordinator.replace(items: items, sourceFolder: root,
                                                      find: "北京公司", replaceWith: "上海集团",
                                                      options: ReplaceOptions(), backupEnabled: false,
                                                      backupRoot: root.appendingPathComponent("备份")) { _ in }
        XCTAssertNil(report.backupDirectory)
        XCTAssertEqual(report.modifiedFiles, 1)
    }

    func testCorruptFileIsReportedNotFatal() async throws {
        try Data("这不是 zip".utf8).write(to: root.appendingPathComponent("坏.docx"))
        let results = await ReplaceCoordinator.scan(folder: root, find: "北京公司",
                                                    options: ReplaceOptions()) { _ in }
        let broken = results.first { $0.relativePath == "坏.docx" }
        if case .failed(let reason)? = broken?.outcome {
            XCTAssertFalse(reason.isEmpty)
        } else {
            XCTFail("损坏文件应标记为失败")
        }

        let items = results.filter { $0.matchCount > 0 }.map(\.item)
        let report = await ReplaceCoordinator.replace(items: items, sourceFolder: root,
                                                      find: "北京公司", replaceWith: "上海集团",
                                                      options: ReplaceOptions(), backupEnabled: true,
                                                      backupRoot: root.appendingPathComponent("备份")) { _ in }
        XCTAssertEqual(report.modifiedFiles, 1, "坏文件不应影响其他文件")
    }

    func testReadOnlyFileIsSkippedAndReported() async throws {
        let file = root.appendingPathComponent("只读.docx")
        try DocxFixture.docx(bodyXML: DocxFixture.paragraph(["旧名"])).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }

        let results = await ReplaceCoordinator.scan(folder: root, find: "旧名",
                                                    options: ReplaceOptions()) { _ in }
        let items = results.filter { $0.matchCount > 0 }.map(\.item)
        let report = await ReplaceCoordinator.replace(items: items, sourceFolder: root,
                                                      find: "旧名", replaceWith: "新名",
                                                      options: ReplaceOptions(), backupEnabled: true,
                                                      backupRoot: root.appendingPathComponent("备份")) { _ in }
        let readOnlyReport = report.failed.first { $0.path == "只读.docx" }
        XCTAssertNotNil(readOnlyReport, "只读文件必须出现在失败列表中")
        XCTAssertTrue(readOnlyReport?.reason.contains("不可写") ?? false)

        // 内容必须原封不动
        let data = try Data(contentsOf: file)
        XCTAssertEqual(try DocxTextReplacer.countMatches(docxData: data, find: "旧名",
                                                         options: ReplaceOptions()), 1)
    }
}
