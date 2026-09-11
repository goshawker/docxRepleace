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
        var hasSpaceAttribute: Bool   // 开标签里存在 xml:space 属性（任何取值）
        var attributes: String   // "<w:t" 之后、">" 或 "/" 之前的原文，首尾空白均原样保留，rebuild 会原样拼回
        var text: String         // 已解码实体的文字
    }

    static func findTextNodes(in xml: [UInt8]) -> [TextNode] {
        var nodes: [TextNode] = []
        var i = 0
        let n = xml.count
        while i < n {
            guard xml[i] == 0x3C else { i += 1; continue }   // '<'

            if matches(xml, at: i, bytes: commentOpen) {
                i = skip(xml, from: i + 4, until: commentClose)
                continue
            }
            if matches(xml, at: i, bytes: cdataOpen) {
                i = skip(xml, from: i + 9, until: cdataClose)
                continue
            }
            if matches(xml, at: i, bytes: piOpen) {
                i = skip(xml, from: i + 2, until: piClose)
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
            let hasSpace = attributes.contains("xml:space")

            if isSelfClosing {
                nodes.append(TextNode(elementStart: i, elementEnd: tagEnd + 1,
                                      innerStart: -1, innerEnd: -1,
                                      isSelfClosing: true, hasSpaceAttribute: hasSpace,
                                      attributes: attributes, text: ""))
                i = tagEnd + 1
            } else {
                let innerStart = tagEnd + 1
                guard let closeStart = findCloseTag(xml, from: innerStart) else { break }
                let closeEnd = findTagEnd(xml, from: closeStart)
                guard closeEnd < n else { break }
                let text = decodeText(Array(xml[innerStart..<closeStart]))
                nodes.append(TextNode(elementStart: i, elementEnd: closeEnd + 1,
                                      innerStart: innerStart, innerEnd: closeStart,
                                      isSelfClosing: false, hasSpaceAttribute: hasSpace,
                                      attributes: attributes, text: text))
                i = closeEnd + 1
            }
        }
        return nodes
    }

    /// 找到 w:t 的结束标签位置，单趟扫描并跳过内部的 CDATA 段（其中可能含 "</w:t" 字节）
    private static func findCloseTag(_ xml: [UInt8], from index: Int) -> Int? {
        var i = index
        while i < xml.count {
            if xml[i] == 0x3C {                                  // '<'
                if matches(xml, at: i, bytes: textClose) { return i }
                if matches(xml, at: i, bytes: cdataOpen) {
                    guard let end = find(xml, from: i + 9, bytes: cdataClose) else { return nil }
                    i = end + 3
                    continue
                }
            }
            i += 1
        }
        return nil
    }

    /// 按 w:t 的出现序号应用新文字，返回新的 XML 字节与**实际应用**的编辑数。
    /// 只重建被编辑的 `w:t` 元素，其余字节原样拼接。
    ///
    /// 序号不变量：序号 i 表示文档顺序中的第 i 个 `w:t`。调用方必须按同样的文档顺序枚举，
    /// 否则会改错元素。调用方还应断言 `applied == edits.count`（越界序号会被丢弃，不报错）。
    static func rebuild(xml: [UInt8], edits: [Int: String]) -> (xml: [UInt8], applied: Int) {
        guard !edits.isEmpty else { return (xml, 0) }
        let nodes = findTextNodes(in: xml)
        let targets: [(node: TextNode, newText: String)] = edits
            .compactMap { index, newText in
                guard index >= 0, index < nodes.count else { return nil }
                return (nodes[index], newText)
            }
            .sorted { $0.node.elementStart < $1.node.elementStart }

        var out = Data()
        var cursor = 0
        for target in targets {
            guard target.node.elementStart >= cursor else { continue }
            out.append(contentsOf: xml[cursor..<target.node.elementStart])
            var attributes = target.node.attributes
            if needsPreserveSpace(target.newText), !target.node.hasSpaceAttribute {
                attributes += " xml:space=\"preserve\""
            }
            out.append(contentsOf: Array("<w:t\(attributes)>\(escape(target.newText))</w:t>".utf8))
            cursor = target.node.elementEnd
        }
        out.append(contentsOf: xml[cursor...])
        return ([UInt8](out), targets.count)
    }

    private static func needsPreserveSpace(_ text: String) -> Bool {
        guard let first = text.unicodeScalars.first, let last = text.unicodeScalars.last else { return false }
        return isSpaceScalar(first) || isSpaceScalar(last)
    }

    // 注意：NBSP(U+00A0) 不算空白 —— Word 不会裁剪它，加 preserve 反而多余
    private static func isSpaceScalar(_ s: UnicodeScalar) -> Bool {
        s == " " || s == "\t" || s == "\n" || s == "\r"
    }

    // MARK: - 字节工具

    // 扫描热路径用的模式字节串，避免每次比较都从 String 构造数组
    private static let commentOpen = [UInt8]("<!--".utf8)
    private static let commentClose = [UInt8]("-->".utf8)
    private static let cdataOpen = [UInt8]("<![CDATA[".utf8)
    private static let cdataClose = [UInt8]("]]>".utf8)
    private static let piOpen = [UInt8]("<?".utf8)
    private static let piClose = [UInt8]("?>".utf8)
    private static let textOpen = [UInt8]("<w:t".utf8)
    private static let textClose = [UInt8]("</w:t".utf8)

    private static func matches(_ xml: [UInt8], at index: Int, bytes pattern: [UInt8]) -> Bool {
        guard index >= 0, index + pattern.count <= xml.count else { return false }
        for k in 0..<pattern.count where xml[index + k] != pattern[k] { return false }
        return true
    }

    private static func matches(_ xml: [UInt8], at index: Int, utf8 pattern: String) -> Bool {
        matches(xml, at: index, bytes: [UInt8](pattern.utf8))
    }

    private static func find(_ xml: [UInt8], from index: Int, bytes pattern: [UInt8]) -> Int? {
        guard !pattern.isEmpty, index >= 0 else { return nil }
        var i = index
        while i + pattern.count <= xml.count {
            if xml[i] == pattern[0], matches(xml, at: i, bytes: pattern) { return i }
            i += 1
        }
        return nil
    }

    private static func find(_ xml: [UInt8], from index: Int, utf8 pattern: String) -> Int? {
        find(xml, from: index, bytes: [UInt8](pattern.utf8))
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
        guard matches(xml, at: index, bytes: textOpen) else { return false }
        let next = index + 4
        guard next < xml.count else { return false }
        let b = xml[next]
        return isWhitespace(b) || b == 0x3E || b == 0x2F
    }

    private static func skip(_ xml: [UInt8], from index: Int, until pattern: [UInt8]) -> Int {
        if let found = find(xml, from: index, bytes: pattern) {
            return found + pattern.count
        }
        return xml.count
    }

    private static func skip(_ xml: [UInt8], from index: Int, until pattern: String) -> Int {
        skip(xml, from: index, until: [UInt8](pattern.utf8))
    }

    private static func decodeText(_ bytes: [UInt8]) -> String {
        var out = ""
        var i = 0
        while i < bytes.count {
            if matches(bytes, at: i, bytes: cdataOpen) {
                guard let end = find(bytes, from: i + 9, bytes: cdataClose) else {
                    out += String(decoding: bytes[i...], as: UTF8.self)
                    break
                }
                out += String(decoding: bytes[(i + 9)..<end], as: UTF8.self)
                i = end + 3
            } else if let next = find(bytes, from: i, bytes: cdataOpen) {
                out += unescape(String(decoding: bytes[i..<next], as: UTF8.self))
                i = next
            } else {
                out += unescape(String(decoding: bytes[i...], as: UTF8.self))
                break
            }
        }
        return out
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
            case "\r": out += "&#13;"
            default: out.append(ch)
            }
        }
        return out
    }
}
