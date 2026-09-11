import XCTest
@testable import DocxReplace

final class DocxTextReplacerTests: XCTestCase {
    private let options = ReplaceOptions()

    private func documentText(_ data: Data) throws -> String {
        let archive = try ZipArchive(data: data)
        let entry = try XCTUnwrap(archive.entry(named: "word/document.xml"))
        return String(decoding: try archive.contents(of: entry), as: UTF8.self)
    }

    func testCountsMatchesAcrossSplitRuns() throws {
        let data = try DocxFixture.docx(bodyXML: DocxFixture.paragraph(["北", "京", "公司"]))
        XCTAssertEqual(try DocxTextReplacer.countMatches(docxData: data, find: "北京公司", options: options), 1)
    }

    func testReplaceKeepsStructureIdentical() throws {
        let data = try DocxFixture.docx(bodyXML: """
        <w:p><w:pPr><w:jc w:val="center"/></w:pPr>\
        <w:r><w:rPr><w:b/></w:rPr><w:t>北</w:t></w:r>\
        <w:r><w:t>京公司</w:t></w:r></w:p>
        """)
        let (out, count) = try DocxTextReplacer.replace(docxData: data, find: "北京公司",
                                                        replaceWith: "上海集团", options: options)
        XCTAssertEqual(count, 1)
        let before = try DocxFixture.structuralSignature(documentText(data))
        let after = try DocxFixture.structuralSignature(documentText(out))
        XCTAssertEqual(before, after, "除 w:t 文字外，XML 结构必须完全一致")
        XCTAssertTrue(try documentText(out).contains("上海集团"))
    }

    func testReplacementInheritsFirstRunFormatting() throws {
        let data = try DocxFixture.docx(bodyXML: """
        <w:p><w:r><w:rPr><w:b/></w:rPr><w:t>北</w:t></w:r><w:r><w:t>京</w:t></w:r></w:p>
        """)
        let (out, _) = try DocxTextReplacer.replace(docxData: data, find: "北京", replaceWith: "上海",
                                                    options: options)
        let xml = try documentText(out)
        XCTAssertTrue(xml.contains("<w:rPr><w:b/></w:rPr><w:t>上海</w:t>"),
                      "替换文字应落在第一个命中的 run 内并继承其格式")
    }

    func testReplacesInHeaderFooterAndTextbox() throws {
        let header = DocxFixture.partXML(prefix: "hdr", bodyXML: DocxFixture.paragraph(["旧名"]))
        let footer = DocxFixture.partXML(prefix: "ftr", bodyXML: DocxFixture.paragraph(["旧名"]))
        let body = """
        <w:p><w:r><w:t>旧名</w:t></w:r></w:p>
        <w:p><w:r><w:drawing><w:txbxContent><w:p><w:r><w:t>旧名</w:t></w:r></w:p></w:txbxContent></w:drawing></w:r></w:p>
        """
        let data = try DocxFixture.docx(bodyXML: body, extraParts: [
            ("word/header1.xml", header),
            ("word/footer1.xml", footer),
        ])
        let (out, count) = try DocxTextReplacer.replace(docxData: data, find: "旧名", replaceWith: "新名",
                                                        options: options)
        XCTAssertEqual(count, 4, "正文 2 处 + 页眉 1 处 + 页脚 1 处")
        let archive = try ZipArchive(data: out)
        for name in ["word/document.xml", "word/header1.xml", "word/footer1.xml"] {
            let entry = try XCTUnwrap(archive.entry(named: name))
            let xml = String(decoding: try archive.contents(of: entry), as: UTF8.self)
            XCTAssertFalse(xml.contains("旧名"), "\(name) 应已替换")
            XCTAssertTrue(xml.contains("新名"), "\(name) 应含新文字")
        }
    }

    func testDoesNotMatchAcrossParagraphs() throws {
        let data = try DocxFixture.docx(bodyXML:
            DocxFixture.paragraph(["北京"]) + DocxFixture.paragraph(["公司"]))
        XCTAssertEqual(try DocxTextReplacer.countMatches(docxData: data, find: "北京公司", options: options), 0)
    }

    func testDoesNotMatchAcrossLineBreak() throws {
        let data = try DocxFixture.docx(bodyXML:
            "<w:p><w:r><w:t>北京</w:t></w:r><w:r><w:br/></w:r><w:r><w:t>公司</w:t></w:r></w:p>")
        XCTAssertEqual(try DocxTextReplacer.countMatches(docxData: data, find: "北京公司", options: options), 0)
    }

    func testNoMatchLeavesDataUntouched() throws {
        let data = try DocxFixture.docx(bodyXML: DocxFixture.paragraph(["内容"]))
        let (out, count) = try DocxTextReplacer.replace(docxData: data, find: "不存在", replaceWith: "x",
                                                        options: options)
        XCTAssertEqual(count, 0)
        XCTAssertEqual(out, data, "没有命中时不应重写文件")
    }

    func testEntitiesSurviveReplacement() throws {
        let data = try DocxFixture.docx(bodyXML: DocxFixture.paragraph(["a &amp; b"]))
        let (out, _) = try DocxTextReplacer.replace(docxData: data, find: "b", replaceWith: "<c>",
                                                    options: options)
        XCTAssertTrue(try documentText(out).contains("a &amp; &lt;c&gt;"))
    }

    func testSpacesAtEdgesGetPreserveSpace() throws {
        let data = try DocxFixture.docx(bodyXML: DocxFixture.paragraph(["X Y"]))
        let (out, _) = try DocxTextReplacer.replace(docxData: data, find: "X", replaceWith: " X ",
                                                    options: options)
        XCTAssertTrue(try documentText(out).contains("xml:space=\"preserve\""))
    }

    func testUntouchedEntriesAreByteIdentical() throws {
        let data = try DocxFixture.docx(bodyXML: DocxFixture.paragraph(["旧名"]))
        let before = try ZipArchive(data: data)
        let rawBefore = try before.rawData(of: try XCTUnwrap(before.entry(named: "_rels/.rels")))
        let (out, _) = try DocxTextReplacer.replace(docxData: data, find: "旧名", replaceWith: "新名",
                                                    options: options)
        let after = try ZipArchive(data: out)
        let rawAfter = try after.rawData(of: try XCTUnwrap(after.entry(named: "_rels/.rels")))
        XCTAssertEqual(rawBefore, rawAfter)
    }

    /// 替换输出的归档必须能被外部工具接受 —— 这是 Task 10 的真实产物形态
    func testRebuiltDocxIsAcceptedBySystemUnzip() throws {
        let data = try DocxFixture.docx(bodyXML: DocxFixture.paragraph(["旧名"]))
        let (out, _) = try DocxTextReplacer.replace(docxData: data, find: "旧名", replaceWith: "新名",
                                                    options: options)
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rebuilt-\(UUID().uuidString).zip")
        try out.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-t", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, "替换产物应通过系统 unzip 校验：\(output)")

        // 逐个条目回读，确认没有部件丢失或损坏
        let archive = try ZipArchive(data: out)
        XCTAssertEqual(archive.entries.count, try ZipArchive(data: data).entries.count)
        for entry in archive.entries {
            XCTAssertNoThrow(try archive.contents(of: entry), "条目应可读：\(entry.name)")
        }
    }

    func testRejectsDuplicateTargetPartNames() throws {
        // 手工拼一个含两个同名 document.xml 的归档（ZipWriter 允许重名）
        let inner = DocxFixture.documentXML(bodyXML: DocxFixture.paragraph(["旧名"]))
        let entries = [
            ZipWriter.makeEntry(name: "[Content_Types].xml",
                                contents: Data(DocxFixture.contentTypesForTest.utf8),
                                date: Date(timeIntervalSince1970: 0)),
            ZipWriter.makeEntry(name: "word/document.xml", contents: Data(inner.utf8),
                                date: Date(timeIntervalSince1970: 0)),
            ZipWriter.makeEntry(name: "word/document.xml", contents: Data(inner.utf8),
                                date: Date(timeIntervalSince1970: 0)),
        ]
        let data = try ZipWriter.build(entries)
        XCTAssertThrowsError(try DocxTextReplacer.countMatches(docxData: data, find: "旧名",
                                                               options: options)) { error in
            XCTAssertEqual(error as? ZipError, .corruptEntry("word/document.xml 在归档中重复出现"))
        }
        XCTAssertThrowsError(try DocxTextReplacer.replace(docxData: data, find: "旧名",
                                                          replaceWith: "新名", options: options))
    }
}
