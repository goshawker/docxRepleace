import Foundation

enum DocxXmlError: Error, Equatable {
    case parseFailed(String)
    case nodeCountMismatch(dom: Int, raw: Int)

    func message(_ s: AppStrings) -> String {
        switch self {
        case .parseFailed(let detail): return s.xmlParseFailed(detail: detail)
        case .nodeCountMismatch(let dom, let raw): return s.xmlNodeCountMismatch(dom: dom, raw: raw)
        }
    }
}

/// 用 XMLDocument 解析出段落结构，解决两件事：
/// 1. 哪些 w:t 属于同一个段落（决定能否跨 run 匹配）
/// 2. 段落内的换行/制表符把文字切成多个片段（匹配不跨片段）
enum DocxXmlAnalyzer {
    struct PartAnalysis: Equatable {
        /// 每个片段包含的 w:t 全局序号。
        /// 注意：顺序不保证按序号升序 —— 父段落的分段会先于其文本框内嵌套段落的分段输出。
        var segments: [[Int]]
        /// 每个 w:t 的文字（下标即全局序号）
        var texts: [String]
    }

    static func analyze(_ xml: [UInt8]) throws -> PartAnalysis {
        let document: XMLDocument
        do {
            document = try XMLDocument(data: Data(xml), options: [])
        } catch {
            throw DocxXmlError.parseFailed(String(describing: error))
        }

        var textNodes: [XMLNode] = []
        var indexByNode: [ObjectIdentifier: Int] = [:]
        func collect(_ node: XMLNode) {
            if node.kind == .element, node.name == "w:t" {
                indexByNode[ObjectIdentifier(node)] = textNodes.count
                textNodes.append(node)
            }
            for child in node.children ?? [] {
                collect(child)
            }
        }
        if let root = document.rootElement() {
            collect(root)
        }

        let rawNodes = XmlTextLocator.findTextNodes(in: xml)
        guard rawNodes.count == textNodes.count else {
            throw DocxXmlError.nodeCountMismatch(dom: textNodes.count, raw: rawNodes.count)
        }

        var segments: [[Int]] = []
        func walkParagraph(_ paragraph: XMLNode) {
            var current: [Int] = []
            func visit(_ node: XMLNode) {
                guard node.kind == .element else { return }
                if node.name == "w:p", node !== paragraph { return }   // 嵌套段落（文本框）单独处理
                if node.name == "w:t" {
                    if let index = indexByNode[ObjectIdentifier(node)] {
                        current.append(index)
                    } else {
                        assertionFailure("w:t 节点未在序号表中，枚举逻辑出现分歧")
                    }
                    return
                }
                if node.name == "w:br" || node.name == "w:tab" || node.name == "w:cr" {
                    if !current.isEmpty {
                        segments.append(current)
                        current = []
                    }
                    return
                }
                for child in node.children ?? [] {
                    visit(child)
                }
            }
            visit(paragraph)
            if !current.isEmpty {
                segments.append(current)
            }
        }

        func collectParagraphs(_ node: XMLNode) {
            if node.kind == .element, node.name == "w:p" {
                walkParagraph(node)
                // 继续下钻：walkParagraph 已跳过嵌套 w:p 的子树，
                // 这里负责把它们（文本框等）当作独立段落再走一遍
            }
            for child in node.children ?? [] {
                collectParagraphs(child)
            }
        }
        if let root = document.rootElement() {
            collectParagraphs(root)
        }

        // 每个 w:t 都必须被分配到某个分段：不在任何 w:p 内的 w:t（第三方工具会产出）
        // 若被静默跳过，既不报错也不处理，宁可整份部件报错
        let assigned = segments.reduce(0) { $0 + $1.count }
        guard assigned == textNodes.count else {
            throw DocxXmlError.nodeCountMismatch(dom: textNodes.count, raw: assigned)
        }

        return PartAnalysis(segments: segments, texts: rawNodes.map(\.text))
    }
}
