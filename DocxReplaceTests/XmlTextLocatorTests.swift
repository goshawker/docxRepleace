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
        XCTAssertTrue(yes[0].hasPreserveSpace)
        let no = nodes("<w:t> x </w:t>")
        XCTAssertFalse(no[0].hasPreserveSpace)
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
}
