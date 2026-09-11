import XCTest
@testable import DocxReplace

final class FileScannerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FileScannerTests-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("子目录"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent(".hidden"), withIntermediateDirectories: true)
        for path in ["A.docx", "子目录/B.docx", "旧.doc", "子目录/旧.doc", "说明.txt", "忽略.md", "~$锁文件.docx"] {
            try Data("x".utf8).write(to: root.appendingPathComponent(path))
        }
        try Data("x".utf8).write(to: root.appendingPathComponent(".hidden/C.docx"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testFindsOnlyWordFilesRecursively() {
        let items = FileScanner.scan(folder: root)
        // 不比较顺序：排序用了本地化比较，顺序随系统语言变化
        XCTAssertEqual(Set(items.map(\.relativePath)),
                       Set(["A.docx", "子目录/B.docx", "子目录/旧.doc", "旧.doc"]))
    }

    func testClassifiesKinds() {
        let items = FileScanner.scan(folder: root)
        XCTAssertEqual(items.first { $0.relativePath == "A.docx" }?.kind, .docx)
        XCTAssertEqual(items.first { $0.relativePath == "旧.doc" }?.kind, .legacyDoc)
    }

    func testSkipsHiddenAndLockFiles() {
        let paths = FileScanner.scan(folder: root).map(\.relativePath)
        XCTAssertFalse(paths.contains { $0.contains(".hidden") })
        XCTAssertFalse(paths.contains { $0.contains("~$") })
    }

    /// 应用放在被扫描的文件夹内时，备份会落在扫描范围内；备份里保存的是替换前的旧文字，
    /// 一旦被扫到，每轮都会「重新找到」它们 —— 替换永远做不完
    func testSkipsBackupDirectories() throws {
        let backupDir = root.appendingPathComponent("DocxReplace备份_2026-09-11_18-07-07/子目录")
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: backupDir.appendingPathComponent("旧版.docx"))

        let paths = FileScanner.scan(folder: root).map(\.relativePath)
        XCTAssertFalse(paths.contains { $0.contains("DocxReplace备份") },
                       "备份目录不得被扫描：\(paths)")
    }
}
