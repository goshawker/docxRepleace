import XCTest
@testable import DocxReplace

final class DocxXmlAnalyzerTests: XCTestCase {
    private func analyze(_ xml: String) throws -> DocxXmlAnalyzer.PartAnalysis {
        // XMLDocument 不接受未声明的命名空间前缀（报 "Namespace prefix w ... is not defined"），
        // 所以测试片段必须包一层声明了 xmlns:w 的根元素，否则所有用例都会在解析阶段失败
        let wrapped = "<w:doc xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">"
            + xml + "</w:doc>"
        return try DocxXmlAnalyzer.analyze([UInt8](wrapped.utf8))
    }

    func testSingleParagraph() throws {
        let xml = "<w:body><w:p><w:r><w:t>甲</w:t></w:r><w:r><w:t>乙</w:t></w:r></w:p></w:body>"
        let result = try analyze(xml)
        XCTAssertEqual(result.segments, [[0, 1]])
        XCTAssertEqual(result.texts, ["甲", "乙"])
    }

    func testTwoParagraphsStaySeparate() throws {
        let xml = "<w:body><w:p><w:r><w:t>甲</w:t></w:r></w:p><w:p><w:r><w:t>乙</w:t></w:r></w:p></w:body>"
        let result = try analyze(xml)
        XCTAssertEqual(result.segments, [[0], [1]])
    }

    func testLineBreakSplitsSegment() throws {
        let xml = "<w:p><w:r><w:t>AB</w:t></w:r><w:r><w:br/></w:r><w:r><w:t>CD</w:t></w:r></w:p>"
        let result = try analyze(xml)
        XCTAssertEqual(result.segments, [[0], [1]])
    }

    func testTabSplitsSegment() throws {
        let xml = "<w:p><w:r><w:t>AB</w:t><w:tab/><w:t>CD</w:t></w:r></w:p>"
        let result = try analyze(xml)
        XCTAssertEqual(result.segments, [[0], [1]])
    }

    func testNestedParagraphInTextBoxIsSeparate() throws {
        let xml = """
        <w:p><w:r><w:t>外层</w:t></w:r><w:r><w:drawing><w:txbxContent>
        <w:p><w:r><w:t>框内</w:t></w:r></w:p>
        </w:txbxContent></w:drawing></w:r></w:p>
        """
        let result = try analyze(xml)
        XCTAssertEqual(result.segments, [[0], [1]])
        XCTAssertEqual(result.texts, ["外层", "框内"])
    }

    func testDelTextIsIgnored() throws {
        let xml = "<w:p><w:del><w:r><w:delText>删除的</w:delText></w:r></w:del><w:r><w:t>保留</w:t></w:r></w:p>"
        let result = try analyze(xml)
        XCTAssertEqual(result.texts, ["保留"])
    }

    func testInstrTextIsIgnored() throws {
        let xml = "<w:p><w:r><w:instrText>PAGE</w:instrText></w:r><w:r><w:t>1</w:t></w:r></w:p>"
        let result = try analyze(xml)
        XCTAssertEqual(result.texts, ["1"])
    }

    func testCommentDoesNotBreakAnalysis() {
        // 注释里的假 w:t 在字节扫描与 DOM 解析中都被忽略，两边数量应一致
        let xml = "<w:p><w:r><w:t>真</w:t><!-- <w:t>假</w:t> --></w:r></w:p>"
        let result = try? analyze(xml)
        XCTAssertEqual(result?.texts, ["真"])
    }

    func testMalformedXMLErrors() {
        XCTAssertThrowsError(try analyze("<w:p><w:r><w:t>未闭合"))
    }

    /// 最关键的假设：字节扫描顺序与 DOM 遍历顺序逐位对应。
    /// 用带注释、delText、文本框嵌套段落的夹具钉死它。
    func testTextsMatchRawScanOrder() throws {
        let xml = """
        <w:p><w:r><w:t>一</w:t></w:r><!-- <w:t>注释</w:t> --><w:r><w:t>二</w:t></w:r></w:p>
        <w:p><w:del><w:r><w:delText>已删</w:delText></w:r></w:del><w:r><w:t>三</w:t></w:r></w:p>
        <w:p><w:r><w:t>四</w:t></w:r><w:r><w:drawing><w:txbxContent>
        <w:p><w:r><w:t>五</w:t></w:r></w:p>
        </w:txbxContent></w:drawing></w:r></w:p>
        """
        let wrapped = "<w:doc xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">"
            + xml + "</w:doc>"
        let bytes = [UInt8](wrapped.utf8)
        let analysis = try DocxXmlAnalyzer.analyze(bytes)
        XCTAssertEqual(analysis.texts, XmlTextLocator.findTextNodes(in: bytes).map(\.text))
        XCTAssertEqual(analysis.texts, ["一", "二", "三", "四", "五"])
    }
}
