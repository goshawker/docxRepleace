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

    /// 词字符 = Unicode 通用类别 L*（字母，含中日韩、扩展区、西夏文等）∪ Nd（十进制数字）。
    ///
    /// 不用 `CharacterSet.letters`：它实测是 L* ∪ M*（多含组合符号），
    /// 且在本机缺少 6 227 个真实字母标量（西夏文 U+17000 起、Todhri U+105C0 起等），
    /// 漏掉字母会把词内命中误判成整词命中，从而改错文字。
    private static func isWordScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber:
            return true
        default:
            return false
        }
    }

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

    /// 判断该 UTF-16 码元位置所在的**完整字符**是否为词字符。
    /// 必须按组合字符序列判断，不能只看单个码元：非 BMP 字符（𝒜、𗀀）是代理对，
    /// 孤立代理项会被误判成词边界。
    private static func isWordCharacter(_ haystack: NSString, at index: Int) -> Bool {
        guard index >= 0, index < haystack.length else { return false }
        let sequence = haystack.rangeOfComposedCharacterSequence(at: index)
        guard let first = haystack.substring(with: sequence).unicodeScalars.first else { return false }
        return isWordScalar(first)
    }

    private static func isWholeWordMatch(_ haystack: NSString, _ found: NSRange) -> Bool {
        if isWordCharacter(haystack, at: found.location - 1) { return false }
        if isWordCharacter(haystack, at: found.location + found.length) { return false }
        return true
    }
}
