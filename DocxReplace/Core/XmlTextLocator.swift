import Foundation

/// 在原始 XML 字节上定位 `w:t` 元素。只在字节层面工作，
/// 因为 UTF-8 的多字节序列不含 ASCII 字节，搜索 ASCII 标记是安全的。
enum XmlTextLocator {
    struct TextNode: Equatable {
        var elementStart: Int
        var elementEnd: Int
        var innerStart: Int      // 自闭合元素为 -1
        var innerEnd: Int
        var isSelfClosing: Bool
        var hasPreserveSpace: Bool
        var attributes: String   // "<w:t" 之后到 ">" 或 "/" 之前的原文（含前导空白）
        var text: String         // 已解码实体的文字
    }

    static func findTextNodes(in xml: [UInt8]) -> [TextNode] {
        var nodes: [TextNode] = []
        var i = 0
        let n = xml.count
        while i < n {
            guard xml[i] == 0x3C else { i += 1; continue }   // '<'

            if matches(xml, at: i, utf8: "<!--") {
                i = skip(xml, from: i + 4, until: "-->")
                continue
            }
            if matches(xml, at: i, utf8: "<![CDATA[") {
                i = skip(xml, from: i + 9, until: "]]>")
                continue
            }
            if matches(xml, at: i, utf8: "<?") {
                i = skip(xml, from: i + 2, until: "?>")
                continue
            }
            guard isTextElementStart(xml, at: i) else { i += 1; continue }

            let tagEnd = findTagEnd(xml, from: i)
            guard tagEnd < n else { break }

            var p = tagEnd - 1
            while p > i, isWhitespace(xml[p]) { p -= 1 }
            let isSelfClosing = xml[p] == 0x2F   // '/'
            let attrStart = i + 4
            let attrEnd = isSelfClosing ? max(attrStart, p) : tagEnd
            let attributes = String(decoding: xml[attrStart..<max(attrStart, attrEnd)], as: UTF8.self)
            let hasPreserve = attributes.contains("xml:space") && attributes.contains("preserve")

            if isSelfClosing {
                nodes.append(TextNode(elementStart: i, elementEnd: tagEnd + 1,
                                      innerStart: -1, innerEnd: -1,
                                      isSelfClosing: true, hasPreserveSpace: hasPreserve,
                                      attributes: attributes, text: ""))
                i = tagEnd + 1
            } else {
                let innerStart = tagEnd + 1
                guard let closeStart = find(xml, from: innerStart, utf8: "</w:t") else { break }
                let closeEnd = findTagEnd(xml, from: closeStart)
                guard closeEnd < n else { break }
                let text = decodeText(Array(xml[innerStart..<closeStart]))
                nodes.append(TextNode(elementStart: i, elementEnd: closeEnd + 1,
                                      innerStart: innerStart, innerEnd: closeStart,
                                      isSelfClosing: false, hasPreserveSpace: hasPreserve,
                                      attributes: attributes, text: text))
                i = closeEnd + 1
            }
        }
        return nodes
    }

    // MARK: - 字节工具

    private static func matches(_ xml: [UInt8], at index: Int, utf8 pattern: String) -> Bool {
        let p = [UInt8](pattern.utf8)
        guard index + p.count <= xml.count else { return false }
        for k in 0..<p.count where xml[index + k] != p[k] { return false }
        return true
    }

    private static func find(_ xml: [UInt8], from index: Int, utf8 pattern: String) -> Int? {
        let p = [UInt8](pattern.utf8)
        guard !p.isEmpty, index >= 0 else { return nil }
        var i = index
        while i + p.count <= xml.count {
            if xml[i] == p[0], matches(xml, at: i, utf8: pattern) { return i }
            i += 1
        }
        return nil
    }

    /// 找到标签的结束 '>'，跳过属性值里的引号内容
    private static func findTagEnd(_ xml: [UInt8], from index: Int) -> Int {
        var i = index
        var quote: UInt8? = nil
        while i < xml.count {
            let b = xml[i]
            if let q = quote {
                if b == q { quote = nil }
            } else if b == 0x22 || b == 0x27 {
                quote = b
            } else if b == 0x3E {
                return i
            }
            i += 1
        }
        return xml.count
    }

    private static func isWhitespace(_ b: UInt8) -> Bool {
        b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D
    }

    /// 判断位置 i 是否是 "<w:t" 且后面紧跟空白、'>' 或 '/'（排除 <w:tab>/<w:tbl> 等）
    private static func isTextElementStart(_ xml: [UInt8], at index: Int) -> Bool {
        guard matches(xml, at: index, utf8: "<w:t") else { return false }
        let next = index + 4
        guard next < xml.count else { return false }
        let b = xml[next]
        return isWhitespace(b) || b == 0x3E || b == 0x2F
    }

    private static func skip(_ xml: [UInt8], from index: Int, until pattern: String) -> Int {
        if let found = find(xml, from: index, utf8: pattern) {
            return found + pattern.utf8.count
        }
        return xml.count
    }

    private static func decodeText(_ bytes: [UInt8]) -> String {
        let s = String(decoding: bytes, as: UTF8.self)
        if s.hasPrefix("<![CDATA[") && s.hasSuffix("]]>") {
            return String(s.dropFirst(9).dropLast(3))
        }
        return unescape(s)
    }

    // MARK: - 实体

    static func unescape(_ s: String) -> String {
        guard s.contains("&") else { return s }
        let chars = Array(s)
        var out = ""
        out.reserveCapacity(chars.count)
        var i = 0
        while i < chars.count {
            guard chars[i] == "&", let semi = chars[i...].firstIndex(of: ";"), semi - i <= 12 else {
                out.append(chars[i]); i += 1; continue
            }
            let entity = String(chars[(i + 1)..<semi])
            var handled = true
            switch entity {
            case "amp": out.append("&")
            case "lt": out.append("<")
            case "gt": out.append(">")
            case "quot": out.append("\"")
            case "apos": out.append("'")
            default:
                if entity.hasPrefix("#x") || entity.hasPrefix("#X"),
                   let v = UInt32(entity.dropFirst(2), radix: 16), let scalar = UnicodeScalar(v) {
                    out.unicodeScalars.append(scalar)
                } else if entity.hasPrefix("#"), let v = UInt32(entity.dropFirst()),
                          let scalar = UnicodeScalar(v) {
                    out.unicodeScalars.append(scalar)
                } else {
                    handled = false
                }
            }
            if handled { i = semi + 1 } else { out.append(chars[i]); i += 1 }
        }
        return out
    }

    static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            default: out.append(ch)
            }
        }
        return out
    }
}
