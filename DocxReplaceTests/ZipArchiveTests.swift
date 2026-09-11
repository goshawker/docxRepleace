import XCTest
@testable import DocxReplace

final class ZipArchiveTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ZipArchiveTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// 用系统 textutil 生成真实 docx
    static func makeRealDocx(text: String, into directory: URL) throws -> URL {
        let htmlURL = directory.appendingPathComponent("source.html")
        let docxURL = directory.appendingPathComponent("source.docx")
        // 必须声明 charset：textutil 的 HTML 解析器在无 charset 时按系统编码（如 GBK）解读，
        // 会把 UTF-8 写入的中文变成乱码，导致 docx 里根本没有原始文字
        try "<html><head><meta charset=\"utf-8\"></head><body><p>\(text)</p></body></html>"
            .write(to: htmlURL, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        process.arguments = ["-convert", "docx", "-output", docxURL.path, htmlURL.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "textutil 生成 docx 失败")
        return docxURL
    }

    func testReadsRealDocx() throws {
        let url = try Self.makeRealDocx(text: "示例文档内容", into: tempDir)
        let archive = try ZipArchive(data: Data(contentsOf: url))
        let entry = try XCTUnwrap(archive.entry(named: "word/document.xml"))
        let xml = try archive.contents(of: entry)
        let text = String(decoding: xml, as: UTF8.self)
        XCTAssertTrue(text.contains("示例文档内容"), "应能解出正文文字")
    }

    func testStoredEntryRoundTrip() throws {
        let payload = Data("stored payload 内容".utf8)
        let entry = ZipOutputEntry(name: "a.txt", dosTime: 0, dosDate: 0, method: 0,
                                   crc32: ZipCRC32.checksum(payload),
                                   uncompressedSize: UInt32(payload.count),
                                   externalAttributes: 0, compressedData: payload)
        let archive = try ZipArchive(data: ZipWriter.build([entry]))
        XCTAssertEqual(try archive.contents(of: try XCTUnwrap(archive.entry(named: "a.txt"))), payload)
    }

    func testDeflatedEntryRoundTrip() throws {
        let payload = Data(String(repeating: "hello world 你好 ", count: 200).utf8)
        let compressed = try XCTUnwrap(ZipCompression.deflate(payload))
        let entry = ZipOutputEntry(name: "dir/b.txt", dosTime: 0, dosDate: 0, method: 8,
                                   crc32: ZipCRC32.checksum(payload),
                                   uncompressedSize: UInt32(payload.count),
                                   externalAttributes: 0, compressedData: compressed)
        let archive = try ZipArchive(data: ZipWriter.build([entry]))
        XCTAssertEqual(try archive.contents(of: try XCTUnwrap(archive.entry(named: "dir/b.txt"))), payload)
    }

    func testRejectsNonZipData() {
        XCTAssertThrowsError(try ZipArchive(data: Data(repeating: 0x41, count: 200)))
    }

    func testDetectsCRCMismatch() throws {
        let payload = Data("hello".utf8)
        let entry = ZipOutputEntry(name: "c.txt", dosTime: 0, dosDate: 0, method: 0,
                                   crc32: 0xDEADBEEF, uncompressedSize: UInt32(payload.count),
                                   externalAttributes: 0, compressedData: payload)
        let archive = try ZipArchive(data: ZipWriter.build([entry]))
        XCTAssertThrowsError(try archive.contents(of: try XCTUnwrap(archive.entry(named: "c.txt"))))
    }
}
