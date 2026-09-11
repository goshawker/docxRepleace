import Foundation

/// .docx 替换引擎。只读分析 + 原始字节改写，未命中的部件原样直拷。
enum DocxTextReplacer {
    static func targetPartNames(in archive: ZipArchive) -> [String] {
        archive.entries.map(\.name).filter { name in
            if name == "word/document.xml" { return true }
            if name == "word/footnotes.xml" || name == "word/endnotes.xml" || name == "word/comments.xml" {
                return true
            }
            guard name.hasPrefix("word/"), !name.dropFirst(5).contains("/") else { return false }
            let file = String(name.dropFirst(5))
            if (file.hasPrefix("header") || file.hasPrefix("footer")), file.hasSuffix(".xml") {
                return true
            }
            return false
        }
    }

    static func countMatches(docxData: Data, find: String, options: ReplaceOptions) throws -> Int {
        guard !find.isEmpty else { return 0 }
        let archive = try ZipArchive(data: docxData)
        var total = 0
        for name in targetPartNames(in: archive) {
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
        let targets = Set(targetPartNames(in: archive))

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
