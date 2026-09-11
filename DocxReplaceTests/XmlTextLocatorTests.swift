import XCTest
@testable import DocxReplace

final class XmlTextLocatorTests: XCTestCase {
    private func nodes(_ xml: String) -> [XmlTextLocator.TextNode] {
        XmlTextLocator.findTextNodes(in: [UInt8](xml.utf8))
    }

    func testFindsSimpleTextNodes() {
        let xml = "<w:p><w:r><w:t>你好</w:t></w:r><w:r><w:t>世界</w:t></w:r></w:p>"
        let result = nodes(xml)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].text, "你好")
        XCTAssertEqual(result[1].text, "世界")
        XCTAssertFalse(result[0].isSelfClosing)
    }

    func testTextPreservesSurroundingPunctuation() {
        let xml = "<w:t>,。！</w:t>"
        XCTAssertEqual(nodes(xml)[0].text, ",。！")
    }

    func testDecodesEntities() {
        let xml = "<w:t>a &amp; b &lt;c&gt; &quot;d&quot; &#65;</w:t>"
        XCTAssertEqual(nodes(xml)[0].text, "a & b <c> \"d\" A")
    }

    func testDetectsPreserveSpaceAttribute() {
        let yes = nodes("<w:t xml:space=\"preserve\"> x </w:t>")
        XCTAssertTrue(yes[0].hasSpaceAttribute)
        let no = nodes("<w:t> x </w:t>")
        XCTAssertFalse(no[0].hasSpaceAttribute)
    }

    func testHandlesSelfClosingTag() {
        let result = nodes("<w:p><w:r><w:t/></w:r></w:p>")
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].isSelfClosing)
        XCTAssertEqual(result[0].text, "")
    }

    func testIgnoresCommentsAndCDATA() {
        let xml = """
        <!-- <w:t>注释里的假元素</w:t> -->
        <w:t>真元素</w:t>
        <![CDATA[ <w:t>CDATA 里的假元素</w:t> ]]>
        """
        let result = nodes(xml)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].text, "真元素")
    }

    func testIgnoresSimilarElementNames() {
        let xml = "<w:tbl><w:tab/><w:tr><w:tc><w:t>唯一</w:t></w:tc></w:tr></w:tbl>"
        let result = nodes(xml)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].text, "唯一")
    }

    func testHandlesAttributesWithGreaterThanSign() {
        let xml = "<w:t w:foo=\"a&gt;b\">文字</w:t>"
        let result = nodes(xml)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].text, "文字")
    }

    func testParagraphIndexRangePointsAtInnerText() {
        let xml = "<w:t>abc</w:t>"
        let bytes = [UInt8](xml.utf8)
        let node = nodes(xml)[0]
        XCTAssertEqual(String(decoding: bytes[node.innerStart..<node.innerEnd], as: UTF8.self), "abc")
        XCTAssertEqual(String(decoding: bytes[node.elementStart..<node.elementEnd], as: UTF8.self), xml)
    }

    private func rebuild(_ xml: String, edits: [Int: String]) -> String {
        String(decoding: XmlTextLocator.rebuild(xml: [UInt8](xml.utf8), edits: edits).xml, as: UTF8.self)
    }

    func testRebuildReplacesOnlyTargetText() {
        let xml = "<w:p><w:r><w:t>北京公司</w:t></w:r></w:p>"
        let out = rebuild(xml, edits: [0: "上海集团"])
        XCTAssertEqual(out, "<w:p><w:r><w:t>上海集团</w:t></w:r></w:p>")
    }

    func testRebuildKeepsRunPropertiesIntact() {
        let xml = "<w:p><w:r><w:rPr><w:b/><w:color w:val=\"FF0000\"/></w:rPr><w:t>旧</w:t></w:r></w:p>"
        let out = rebuild(xml, edits: [0: "新"])
        XCTAssertEqual(out, "<w:p><w:r><w:rPr><w:b/><w:color w:val=\"FF0000\"/></w:rPr><w:t>新</w:t></w:r></w:p>")
    }

    func testRebuildAddsPreserveSpaceWhenNeeded() {
        let out = rebuild("<w:t>abc</w:t>", edits: [0: " abc "])
        XCTAssertEqual(out, "<w:t xml:space=\"preserve\"> abc </w:t>")
    }

    func testRebuildDoesNotDuplicatePreserveSpace() {
        let out = rebuild("<w:t xml:space=\"preserve\">abc</w:t>", edits: [0: " abc "])
        XCTAssertEqual(out, "<w:t xml:space=\"preserve\"> abc </w:t>")
    }

    func testRebuildEscapesEntities() {
        let out = rebuild("<w:t>x</w:t>", edits: [0: "a & b <c>"])
        XCTAssertEqual(out, "<w:t>a &amp; b &lt;c&gt;</w:t>")
    }

    func testRebuildConvertsSelfClosingTag() {
        let out = rebuild("<w:p><w:r><w:t/></w:r></w:p>", edits: [0: "填入"])
        XCTAssertEqual(out, "<w:p><w:r><w:t>填入</w:t></w:r></w:p>")
    }

    func testRebuildCanEmptyText() {
        let out = rebuild("<w:t>要删掉</w:t>", edits: [0: ""])
        XCTAssertEqual(out, "<w:t></w:t>")
    }

    func testRebuildHandlesMultipleEditsAndAttributeOrder() {
        let xml = "<w:r><w:t xml:space=\"preserve\">A</w:t></w:r><w:r><w:t>B</w:t></w:r>"
        let out = rebuild(xml, edits: [0: "AAA", 1: "BBB"])
        XCTAssertEqual(out, "<w:r><w:t xml:space=\"preserve\">AAA</w:t></w:r><w:r><w:t>BBB</w:t></w:r>")
    }

    func testRebuildLeavesOtherElementsAlone() {
        let xml = "<w:p><w:pPr><w:jc w:val=\"center\"/></w:pPr><w:r><w:t>旧</w:t></w:r></w:p>"
        let out = rebuild(xml, edits: [0: "新"])
        XCTAssertEqual(out, "<w:p><w:pPr><w:jc w:val=\"center\"/></w:pPr><w:r><w:t>新</w:t></w:r></w:p>")
    }

    func testRebuildWithNoEditsReturnsInput() {
        let xml = "<w:t>原样</w:t>"
        XCTAssertEqual(rebuild(xml, edits: [:]), xml)
    }

    func testIgnoresCloseTagInsideCDATA() {
        let xml = "<w:t><![CDATA[a</w:t>b]]></w:t>"
        let result = nodes(xml)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].text, "a</w:t>b")
        let bytes = [UInt8](xml.utf8)
        XCTAssertEqual(String(decoding: bytes[result[0].innerStart..<result[0].innerEnd], as: UTF8.self),
                       "<![CDATA[a</w:t>b]]>")
    }

    func testDecodesMixedCDATAContent() {
        XCTAssertEqual(nodes("<w:t>pre<![CDATA[<&]]>post</w:t>")[0].text, "pre<&post")
    }

    func testRebuildReportsAppliedCountAndDropsBadKeys() {
        let xml = "<w:t>a</w:t><w:t>b</w:t>"
        let result = XmlTextLocator.rebuild(xml: [UInt8](xml.utf8), edits: [0: "X", 99: "Y", -1: "Z"])
        XCTAssertEqual(result.applied, 1)
        XCTAssertEqual(String(decoding: result.xml, as: UTF8.self), "<w:t>X</w:t><w:t>b</w:t>")
    }

    func testRebuildPreservesOtherAttributesOnEditedElement() {
        let out = rebuild("<w:t w:rsidR=\"00AB12\">旧</w:t>", edits: [0: "新"])
        XCTAssertEqual(out, "<w:t w:rsidR=\"00AB12\">新</w:t>")
    }

    func testRebuildSelfClosingWithExistingAttribute() {
        let out = rebuild("<w:t xml:space=\"preserve\"/>", edits: [0: " x"])
        XCTAssertEqual(out, "<w:t xml:space=\"preserve\"> x</w:t>")
    }

    func testRebuildDoesNotDuplicateExplicitDefaultSpace() {
        let out = rebuild("<w:t xml:space=\"default\">abc</w:t>", edits: [0: " abc "])
        XCTAssertEqual(out, "<w:t xml:space=\"default\"> abc </w:t>")
    }

    func testRebuildEscapesCarriageReturn() {
        XCTAssertEqual(rebuild("<w:t>x</w:t>", edits: [0: "a\rb"]), "<w:t>a&#13;b</w:t>")
    }

    func testLeadingSpaceBeforeCombiningMarkGetsPreserve() {
        // 前导空格后紧跟组合字符：按 Character 判断会误判，必须按 UnicodeScalar
        let out = rebuild("<w:t>x</w:t>", edits: [0: " \u{0301}abc"])
        XCTAssertEqual(out, "<w:t xml:space=\"preserve\"> \u{0301}abc</w:t>")
    }
}
