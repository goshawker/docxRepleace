import XCTest
@testable import DocxReplace

final class BackupManagerTests: XCTestCase {
    private var root: URL!
    private var source: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("BackupTests-\(UUID().uuidString)")
        source = root.appendingPathComponent("源文件夹")
        try FileManager.default.createDirectory(at: source.appendingPathComponent("子目录"),
                                                withIntermediateDirectories: true)
        try Data("原始内容".utf8).write(to: source.appendingPathComponent("子目录/文件.docx"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testBackupPreservesRelativePathAndContent() throws {
        let runDir = try BackupManager.makeRunDirectory(root: root.appendingPathComponent("备份"),
                                                        sourceFolder: source,
                                                        date: Date(timeIntervalSince1970: 0))
        try BackupManager.backup(fileURL: source.appendingPathComponent("子目录/文件.docx"),
                                 sourceFolder: source, runDirectory: runDir)
        let restored = runDir.appendingPathComponent("子目录/文件.docx")
        XCTAssertTrue(FileManager.default.fileExists(atPath: restored.path))
        XCTAssertEqual(try Data(contentsOf: restored), Data("原始内容".utf8))
    }

    func testRunDirectoryIncludesSourceFolderName() throws {
        let runDir = try BackupManager.makeRunDirectory(root: root.appendingPathComponent("备份"),
                                                        sourceFolder: source,
                                                        date: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(runDir.lastPathComponent, "源文件夹")
        XCTAssertTrue(runDir.path.contains("DocxReplace备份_"))
    }

    func testBackupOverwritesExistingCopy() throws {
        let runDir = try BackupManager.makeRunDirectory(root: root.appendingPathComponent("备份"),
                                                        sourceFolder: source, date: Date())
        let file = source.appendingPathComponent("子目录/文件.docx")
        try BackupManager.backup(fileURL: file, sourceFolder: source, runDirectory: runDir)
        try Data("改过了".utf8).write(to: file)
        try BackupManager.backup(fileURL: file, sourceFolder: source, runDirectory: runDir)
        let restored = runDir.appendingPathComponent("子目录/文件.docx")
        XCTAssertEqual(try Data(contentsOf: restored), Data("改过了".utf8))
    }
}
