import XCTest
@testable import DocxReplace

/// 用系统 textutil 生成的真实 docx 做端到端验证，
/// 并用 textutil 反向读取验证输出文件仍然是 Word 能打开的合法文档。
final class EndToEndTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("EndToEndTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeDocx(html: String) throws -> Data {
        let htmlURL = tempDir.appendingPathComponent("in-\(UUID().uuidString).html")
        let docxURL = tempDir.appendingPathComponent("out-\(UUID().uuidString).docx")
        // 必须显式声明 charset：textutil 的 HTML 导入在中文系统下会按 GBK 解释，
        // 不加这行会导致 docx 里的中文变成乱码
        let htmlWithCharset = html.contains("charset")
            ? html
            : html.replacingOccurrences(of: "<html>", with: "<html><head><meta charset=\"utf-8\"></head>")
        try htmlWithCharset.write(to: htmlURL, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        process.arguments = ["-convert", "docx", "-output", docxURL.path, htmlURL.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return try Data(contentsOf: docxURL)
    }

    private func plainText(of data: Data) throws -> String {
        let docxURL = tempDir.appendingPathComponent("verify-\(UUID().uuidString).docx")
        try data.write(to: docxURL)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        process.arguments = ["-convert", "txt", "-stdout", docxURL.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "输出文件应是系统可解析的合法 docx")
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    func testReplacesTextInRealDocx() throws {
        let data = try makeDocx(html: "<html><body><p>北京某某科技有限公司</p><p>其他内容</p></body></html>")
        let options = ReplaceOptions()
        XCTAssertEqual(try DocxTextReplacer.countMatches(docxData: data, find: "北京某某科技",
                                                         options: options), 1)

        let (out, count) = try DocxTextReplacer.replace(docxData: data, find: "北京某某科技",
                                                        replaceWith: "上海新兴", options: options)
        XCTAssertEqual(count, 1)
        let text = try plainText(of: out)
        XCTAssertTrue(text.contains("上海新兴有限公司"), "实际文本：\(text)")
        XCTAssertFalse(text.contains("北京某某科技"))
    }

    func testStructuralSignatureUnchangedOnRealDocx() throws {
        let data = try makeDocx(html: "<html><body><p>待替换文字 测试</p></body></html>")
        let archiveBefore = try ZipArchive(data: data)
        let xmlBefore = String(decoding:
            try archiveBefore.contents(of: try XCTUnwrap(archiveBefore.entry(named: "word/document.xml"))),
            as: UTF8.self)

        let (out, _) = try DocxTextReplacer.replace(docxData: data, find: "待替换", replaceWith: "已修改",
                                                    options: ReplaceOptions())
        let archiveAfter = try ZipArchive(data: out)
        let xmlAfter = String(decoding:
            try archiveAfter.contents(of: try XCTUnwrap(archiveAfter.entry(named: "word/document.xml"))),
            as: UTF8.self)

        XCTAssertEqual(try DocxFixture.structuralSignature(xmlBefore),
                       try DocxFixture.structuralSignature(xmlAfter))
    }

    func testAllNonTargetPartsAreByteIdentical() throws {
        let data = try makeDocx(html: "<html><body><p>旧名 公司</p></body></html>")
        let before = try ZipArchive(data: data)
        let (out, _) = try DocxTextReplacer.replace(docxData: data, find: "旧名", replaceWith: "新名",
                                                    options: ReplaceOptions())
        let after = try ZipArchive(data: out)
        for entry in before.entries where entry.name != "word/document.xml" {
            guard let afterEntry = after.entry(named: entry.name) else {
                XCTFail("条目丢失：\(entry.name)"); continue
            }
            XCTAssertEqual(try before.rawData(of: entry), try after.rawData(of: afterEntry),
                           "未改动条目应字节级一致：\(entry.name)")
        }
    }
}
