import Foundation

/// 在一个段落（或段落内被换行/制表符切分出的片段）的文字上做查找与替换。
/// texts 按 w:t 出现顺序给出，返回的 Edit.textIndex 即该数组下标。
///
/// 所有偏移量一律以 **UTF-16 码元** 计。原因：
/// 1. UTF-16 偏移在字符串拼接时是可加的，而 Character 偏移不是 —— 当一个字素簇横跨
///    两个 run（组合符、肤色 emoji、国旗、韩文拼字、ZWJ 序列）时，按 Character 累加的
///    run 起始偏移会与拼接串中的实际位置错位，导致静默改错文字。
/// 2. 与 Foundation 的 NSString 匹配 API 单位一致，代码里不再出现 String.Index 运算，
///    也就不会因索引落在字素簇内部而崩溃。
enum ParagraphMatcher {
    struct Edit: Equatable {
        var textIndex: Int
        var newText: String
    }

    /// 词字符集合：字母与数字（含中日韩文字）。与 Word 的「全字匹配」行为一致。
    private static let wordCharacters = CharacterSet.letters.union(.decimalDigits)

    static func countMatches(in texts: [String], find: String, options: ReplaceOptions) -> Int {
        guard !find.isEmpty else { return 0 }
        return matchRanges(in: texts.joined(), find: find, options: options).count
    }

    static func replace(in texts: [String], find: String, replaceWith: String,
                        options: ReplaceOptions) -> [Edit] {
        guard !find.isEmpty, !texts.isEmpty else { return [] }
        let matches = matchRanges(in: texts.joined(), find: find, options: options)
        guard !matches.isEmpty else { return [] }

        var starts: [Int] = []
        var offset = 0
        for text in texts {
            starts.append(offset)
            offset += text.utf16.count
        }

        var editsByText: [Int: [(range: Range<Int>, replacement: String)]] = [:]
        for match in matches {
            func overlaps(_ index: Int) -> Bool {
                starts[index] < match.upperBound && starts[index] + texts[index].utf16.count > match.lowerBound
            }
            guard let first = texts.indices.first(where: overlaps),
                  let last = texts.indices.last(where: overlaps) else { continue }
            for index in first...last {
                let localStart = max(match.lowerBound - starts[index], 0)
                let localEnd = min(match.upperBound - starts[index], texts[index].utf16.count)
                // 空区间只在「整段都空」时出现（例如夹在命中中间的零长 run），跳过以免产生空改动
                guard localStart < localEnd else { continue }
                editsByText[index, default: []].append((localStart..<localEnd, index == first ? replaceWith : ""))
            }
        }

        var edits: [Edit] = []
        for (index, changes) in editsByText {
            let mutable = NSMutableString(string: texts[index])
            for change in changes.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
                mutable.replaceCharacters(
                    in: NSRange(location: change.range.lowerBound,
                                length: change.range.upperBound - change.range.lowerBound),
                    with: change.replacement)
            }
            edits.append(Edit(textIndex: index, newText: mutable as String))
        }
        return edits.sorted { $0.textIndex < $1.textIndex }
    }

    /// 返回命中在拼接字符串中的位置，单位为 **UTF-16 码元**，互不重叠
    static func matchRanges(in text: String, find: String, options: ReplaceOptions) -> [Range<Int>] {
        guard !find.isEmpty, !text.isEmpty else { return [] }
        let haystack = text as NSString
        var compareOptions: NSString.CompareOptions = [.literal]
        if !options.caseSensitive { compareOptions.insert(.caseInsensitive) }

        var ranges: [Range<Int>] = []
        var location = 0
        while location < haystack.length {
            let searchRange = NSRange(location: location, length: haystack.length - location)
            let found = haystack.range(of: find, options: compareOptions, range: searchRange)
            guard found.location != NSNotFound else { break }
            if !options.wholeWord || isWholeWordMatch(haystack, found) {
                ranges.append(found.location..<(found.location + found.length))
            }
            location = found.location + max(found.length, 1)   // 至少前进 1，避免零长命中死循环
        }
        return ranges
    }

    /// 前后紧邻的码元是否都不是词字符。只检查边界那一个码元，不做任何索引运算。
    private static func isWholeWordMatch(_ haystack: NSString, _ found: NSRange) -> Bool {
        if found.location > 0 {
            let before = NSRange(location: found.location - 1, length: 1)
            if haystack.rangeOfCharacter(from: wordCharacters, range: before).location != NSNotFound {
                return false
            }
        }
        let afterStart = found.location + found.length
        if afterStart < haystack.length {
            let after = NSRange(location: afterStart, length: 1)
            if haystack.rangeOfCharacter(from: wordCharacters, range: after).location != NSNotFound {
                return false
            }
        }
        return true
    }
}
