import Foundation
@testable import DocxReplace

/// 用自研 ZIP 层拼出结构合法的 .docx，用于测试
enum DocxFixture {
    static func docx(bodyXML: String, extraParts: [(String, String)] = []) throws -> Data {
        var parts: [(String, String)] = [
            ("[Content_Types].xml", contentTypes(extraParts: extraParts.map(\.0))),
            ("_rels/.rels", rootRels),
            ("word/document.xml", documentXML(bodyXML: bodyXML)),
        ]
        parts.append(contentsOf: extraParts)
        let entries = parts.map {
            ZipWriter.makeEntry(name: $0.0, contents: Data($0.1.utf8), date: Date(timeIntervalSince1970: 0))
        }
        return try ZipWriter.build(entries)
    }

    static func paragraph(_ runs: [String]) -> String {
        "<w:p>" + runs.map { "<w:r><w:t>\($0)</w:t></w:r>" }.joined() + "</w:p>"
    }

    /// 把 XML 中所有 w:t 元素内容清空，用于「除文字外结构完全一致」的比对
    static func structuralSignature(_ xml: String) throws -> String {
        let regex = try NSRegularExpression(pattern: "<w:t(?:\\s[^>]*)?(?:/>|>[^<]*</w:t>)")
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        return regex.stringByReplacingMatches(in: xml, range: range, withTemplate: "<w:t/>")
    }

    private static func contentTypes(extraParts: [String]) -> String {
        var overrides = """
        <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        """
        for name in extraParts {
            let type: String
            if name.contains("header") {
                type = "application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"
            } else if name.contains("footer") {
                type = "application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"
            } else if name.contains("footnotes") {
                type = "application/vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml"
            } else if name.contains("endnotes") {
                type = "application/vnd.openxmlformats-officedocument.wordprocessingml.endnotes+xml"
            } else {
                type = "application/vnd.openxmlformats-officedocument.wordprocessingml.comments+xml"
            }
            overrides += "\n<Override PartName=\"/\(name)\" ContentType=\"\(type)\"/>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        \(overrides)
        </Types>
        """
    }

    private static let rootRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
    </Relationships>
    """

    static func documentXML(bodyXML: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>
        \(bodyXML)
        <w:sectPr/></w:body></w:document>
        """
    }

    static func partXML(prefix: String, bodyXML: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:\(prefix) xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        \(bodyXML)
        </w:\(prefix)>
        """
    }
}
