import Foundation

/// .docx 替换引擎。只读分析 + 原始字节改写，未命中的部件原样直拷。
enum DocxTextReplacer {
    static func targetPartNames(in archive: ZipArchive) throws -> [String] {
        var names: [String] = []
        for entry in archive.entries where isTargetPart(entry.name) {
            if names.contains(entry.name) {
                // 重名会让「按名取第一个」与「按名改写全部」错位：第二个条目会被整体覆盖，
                // 计数也会翻倍。Word 不会产出，但第三方工具可能，必须响亮失败。
                throw ZipError.corruptEntry("\(entry.name) 在归档中重复出现")
            }
            names.append(entry.name)
        }
        return names
    }

    /// 目标部件：正文、页眉、页脚、脚注、尾注、批注
    private static func isTargetPart(_ name: String) -> Bool {
        if name == "word/document.xml" { return true }
        if name == "word/footnotes.xml" || name == "word/endnotes.xml" || name == "word/comments.xml" {
            return true
        }
        guard name.hasPrefix("word/"), !name.dropFirst(5).contains("/") else { return false }
        let file = String(name.dropFirst(5))
        return (file.hasPrefix("header") || file.hasPrefix("footer")) && file.hasSuffix(".xml")
    }

    static func countMatches(docxData: Data, find: String, options: ReplaceOptions) throws -> Int {
        guard !find.isEmpty else { return 0 }
        let archive = try ZipArchive(data: docxData)
        var total = 0
        for name in try targetPartNames(in: archive) {
            guard let entry = archive.entry(named: name) else { continue }
            let xml = [UInt8](try archive.contents(of: entry))
            let analysis = try DocxXmlAnalyzer.analyze(xml)
            for segment in analysis.segments {
                total += ParagraphMatcher.countMatches(in: segment.map { analysis.texts[$0] },
                                                       find: find, options: options)
            }
        }
        return total
    }

    /// 返回新数据与实际替换处数；没有命中时原样返回输入数据
    static func replace(docxData: Data, find: String, replaceWith: String,
                        options: ReplaceOptions) throws -> (data: Data, replacedCount: Int) {
        guard !find.isEmpty else { return (docxData, 0) }
        let archive = try ZipArchive(data: docxData)
        let targets = Set(try targetPartNames(in: archive))

        var partEdits: [String: (xml: [UInt8], edits: [Int: String], count: Int)] = [:]
        for name in targets {
            guard let entry = archive.entry(named: name) else { continue }
            let xml = [UInt8](try archive.contents(of: entry))
            let analysis = try DocxXmlAnalyzer.analyze(xml)
            var edits: [Int: String] = [:]
            var count = 0
            for segment in analysis.segments {
                let texts = segment.map { analysis.texts[$0] }
                count += ParagraphMatcher.countMatches(in: texts, find: find, options: options)
                for edit in ParagraphMatcher.replace(in: texts, find: find, replaceWith: replaceWith,
                                                     options: options) {
                    edits[segment[edit.textIndex]] = edit.newText
                }
            }
            if count > 0 {
                partEdits[name] = (xml, edits, count)
            }
        }
        guard !partEdits.isEmpty else { return (docxData, 0) }

        var outputs: [ZipOutputEntry] = []
        var total = 0
        for entry in archive.entries {
            if let changed = partEdits[entry.name] {
                let rebuilt = XmlTextLocator.rebuild(xml: changed.xml, edits: changed.edits)
                // 序号必须全部命中：rebuild 会静默丢弃越界序号，宁可整份文件报错，
                // 也不能出现「只改了一部分却按全部成功上报」
                guard rebuilt.applied == changed.edits.count else {
                    throw DocxXmlError.nodeCountMismatch(dom: rebuilt.applied, raw: changed.edits.count)
                }
                let newXML = rebuilt.xml
                // 最后一道防线：改写后的 XML 必须仍能被完整解析。
                // 宁可整份文件报错跳过，也不能写出 Word 打不开的文档。
                _ = try XMLDocument(data: Data(newXML), options: [])
                outputs.append(ZipWriter.makeEntry(name: entry.name, contents: Data(newXML),
                                                   date: Date(),
                                                   externalAttributes: entry.externalAttributes))
                total += changed.count
            } else {
                outputs.append(ZipWriter.copyEntry(entry, raw: try archive.rawData(of: entry)))
            }
        }
        return (try ZipWriter.build(outputs), total)
    }
}
