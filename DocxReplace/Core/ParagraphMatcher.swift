import Foundation

/// 在一个段落（或段落内被换行/制表符切分出的片段）的文字上做查找与替换。
/// texts 按 w:t 出现顺序给出，返回的 Edit.textIndex 即该数组下标。
enum ParagraphMatcher {
    struct Edit: Equatable {
        var textIndex: Int
        var newText: String
    }

    static func countMatches(in texts: [String], find: String, options: ReplaceOptions) -> Int {
        guard !find.isEmpty else { return 0 }
        return matchRanges(in: texts.joined(), find: find, options: options).count
    }

    static func replace(in texts: [String], find: String, replaceWith: String,
                        options: ReplaceOptions) -> [Edit] {
        guard !find.isEmpty, !texts.isEmpty else { return [] }
        let joined = texts.joined()
        let matches = matchRanges(in: joined, find: find, options: options)
        guard !matches.isEmpty else { return [] }

        var starts: [Int] = []
        var offset = 0
        for text in texts {
            starts.append(offset)
            offset += text.count
        }

        var editsByText: [Int: [(range: Range<Int>, replacement: String)]] = [:]
        for match in matches {
            func overlaps(_ index: Int) -> Bool {
                starts[index] < match.upperBound && starts[index] + texts[index].count > match.lowerBound
            }
            guard let first = texts.indices.first(where: overlaps),
                  let last = texts.indices.last(where: overlaps) else { continue }
            for index in first...last {
                let localStart = max(match.lowerBound - starts[index], 0)
                let localEnd = min(match.upperBound - starts[index], texts[index].count)
                guard localStart <= localEnd else { continue }
                editsByText[index, default: []].append((localStart..<localEnd, index == first ? replaceWith : ""))
            }
        }

        var edits: [Edit] = []
        for (index, changes) in editsByText {
            var chars = Array(texts[index])
            for change in changes.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
                chars.replaceSubrange(change.range, with: Array(change.replacement))
            }
            edits.append(Edit(textIndex: index, newText: String(chars)))
        }
        return edits.sorted { $0.textIndex < $1.textIndex }
    }

    /// 返回命中在拼接字符串中的位置（以 Character 计）
    static func matchRanges(in text: String, find: String, options: ReplaceOptions) -> [Range<Int>] {
        guard !find.isEmpty, !text.isEmpty else { return [] }
        var compareOptions: String.CompareOptions = [.literal]
        if !options.caseSensitive { compareOptions.insert(.caseInsensitive) }

        var ranges: [Range<Int>] = []
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let found = text.range(of: find, options: compareOptions, range: searchStart..<text.endIndex) {
            if !options.wholeWord || isWholeWord(text, found) {
                ranges.append(text.distance(from: text.startIndex, to: found.lowerBound)
                              ..< text.distance(from: text.startIndex, to: found.upperBound))
            }
            searchStart = found.upperBound
        }
        return ranges
    }

    private static func isWholeWord(_ text: String, _ range: Range<String.Index>) -> Bool {
        if range.lowerBound > text.startIndex {
            let before = text[text.index(before: range.lowerBound)]
            if isWordCharacter(before) { return false }
        }
        if range.upperBound < text.endIndex {
            let after = text[range.upperBound]
            if isWordCharacter(after) { return false }
        }
        return true
    }

    private static func isWordCharacter(_ ch: Character) -> Bool {
        ch.isLetter || ch.isNumber
    }
}
