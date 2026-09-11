import XCTest
@testable import DocxReplace

final class ParagraphMatcherTests: XCTestCase {
    private let options = ReplaceOptions()

    func testCountsAcrossSplitRuns() {
        let texts = ["北", "京公", "司"]
        XCTAssertEqual(ParagraphMatcher.countMatches(in: texts, find: "北京公司", options: options), 1)
    }

    func testCountsMultipleOccurrencesInOneRun() {
        XCTAssertEqual(ParagraphMatcher.countMatches(in: ["abcabc"], find: "abc", options: options), 2)
    }

    func testNonOverlappingMatches() {
        XCTAssertEqual(ParagraphMatcher.countMatches(in: ["aaaa"], find: "aa", options: options), 2)
    }

    func testCaseInsensitiveByDefault() {
        XCTAssertEqual(ParagraphMatcher.countMatches(in: ["Hello World"], find: "hello", options: options), 1)
    }

    func testCaseSensitiveOption() {
        let opts = ReplaceOptions(caseSensitive: true)
        XCTAssertEqual(ParagraphMatcher.countMatches(in: ["Hello World"], find: "hello", options: opts), 0)
        XCTAssertEqual(ParagraphMatcher.countMatches(in: ["Hello World"], find: "Hello", options: opts), 1)
    }

    func testWholeWordOption() {
        let opts = ReplaceOptions(wholeWord: true)
        XCTAssertEqual(ParagraphMatcher.countMatches(in: ["cat category"], find: "cat", options: opts), 1)
        XCTAssertEqual(ParagraphMatcher.countMatches(in: ["a cat."], find: "cat", options: opts), 1)
    }

    func testEmptyFindTextMatchesNothing() {
        XCTAssertEqual(ParagraphMatcher.countMatches(in: ["abc"], find: "", options: options), 0)
    }

    func testNoMatchReturnsZero() {
        XCTAssertEqual(ParagraphMatcher.countMatches(in: ["abc"], find: "xyz", options: options), 0)
    }

    func testCountsAcrossManyRunsAndSegments() {
        let texts = ["公司", "名称", "是", "北京", "公司"]
        XCTAssertEqual(ParagraphMatcher.countMatches(in: texts, find: "公司", options: options), 2)
    }

    func testReplaceWithinSingleRun() {
        let edits = ParagraphMatcher.replace(in: ["北京公司"], find: "北京", replaceWith: "上海", options: options)
        XCTAssertEqual(edits, [ParagraphMatcher.Edit(textIndex: 0, newText: "上海公司")])
    }

    func testReplaceAcrossRunsPutsTextInFirstRun() {
        let edits = ParagraphMatcher.replace(in: ["北", "京", "公司"], find: "北京", replaceWith: "上海",
                                             options: options)
        XCTAssertEqual(edits, [
            ParagraphMatcher.Edit(textIndex: 0, newText: "上海"),
            ParagraphMatcher.Edit(textIndex: 1, newText: ""),
        ])
    }

    func testReplaceAcrossRunsKeepsSuffix() {
        let edits = ParagraphMatcher.replace(in: ["AB", "CD", "EF"], find: "BC", replaceWith: "X",
                                             options: options)
        XCTAssertEqual(edits, [
            ParagraphMatcher.Edit(textIndex: 0, newText: "AX"),
            ParagraphMatcher.Edit(textIndex: 1, newText: "D"),
        ])
    }

    func testReplaceWithLongerText() {
        let edits = ParagraphMatcher.replace(in: ["abc"], find: "b", replaceWith: "BETA", options: options)
        XCTAssertEqual(edits, [ParagraphMatcher.Edit(textIndex: 0, newText: "aBETAc")])
    }

    func testReplaceWithEmptyStringDeletes() {
        let edits = ParagraphMatcher.replace(in: ["aXbXc"], find: "X", replaceWith: "", options: options)
        XCTAssertEqual(edits, [ParagraphMatcher.Edit(textIndex: 0, newText: "abc")])
    }

    func testReplaceMultipleMatchesInOneRun() {
        let edits = ParagraphMatcher.replace(in: ["old-old"], find: "old", replaceWith: "new", options: options)
        XCTAssertEqual(edits, [ParagraphMatcher.Edit(textIndex: 0, newText: "new-new")])
    }

    func testReplaceMatchSpanningTwoRunsEditsBoth() {
        // joined = "abab"，"ba" 命中 [1,3)，横跨 run0 的 'b' 与 run1 的 'a'，
        // 因此两个 run 都必须重写（run1 若不动，残留的 'a' 会留下）
        let edits = ParagraphMatcher.replace(in: ["ab", "ab"], find: "ba", replaceWith: "X", options: options)
        XCTAssertEqual(edits, [ParagraphMatcher.Edit(textIndex: 0, newText: "aX"),
                               ParagraphMatcher.Edit(textIndex: 1, newText: "b")])
    }

    func testReplaceSkipsEmptySegments() {
        let edits = ParagraphMatcher.replace(in: ["", ""], find: "x", replaceWith: "y", options: options)
        XCTAssertTrue(edits.isEmpty)
    }

    func testReplaceCaseInsensitiveKeepsReplacementVerbatim() {
        let edits = ParagraphMatcher.replace(in: ["HELLO"], find: "hello", replaceWith: "hi", options: options)
        XCTAssertEqual(edits, [ParagraphMatcher.Edit(textIndex: 0, newText: "hi")])
    }

    func testReplaceWholeWordOnly() {
        let opts = ReplaceOptions(wholeWord: true)
        let edits = ParagraphMatcher.replace(in: ["cat category"], find: "cat", replaceWith: "dog", options: opts)
        XCTAssertEqual(edits, [ParagraphMatcher.Edit(textIndex: 0, newText: "dog category")])
    }

    func testReplaceNothingReturnsEmpty() {
        XCTAssertTrue(ParagraphMatcher.replace(in: ["abc"], find: "zzz", replaceWith: "y",
                                               options: options).isEmpty)
    }

    func testCombiningMarkSplitAcrossRuns() {
        // "a" + 组合符 拼成一个字素簇：按 Character 计偏移会错位，必须按 UTF-16
        let edits = ParagraphMatcher.replace(in: ["a", "\u{0301}b"], find: "b", replaceWith: "X",
                                             options: options)
        XCTAssertEqual(edits, [ParagraphMatcher.Edit(textIndex: 1, newText: "\u{0301}X")])
    }

    func testEmojiSkinToneSplitAcrossRuns() {
        let edits = ParagraphMatcher.replace(in: ["👍", "🏽x"], find: "x", replaceWith: "X", options: options)
        XCTAssertEqual(edits, [ParagraphMatcher.Edit(textIndex: 1, newText: "🏽X")])
    }

    func testWholeWordWithFlagEmojiDoesNotCrash() {
        let opts = ReplaceOptions(caseSensitive: true, wholeWord: true)
        XCTAssertEqual(ParagraphMatcher.matchRanges(in: "🇳🇨", find: "🇨", options: opts), [2..<4])
    }

    func testCountAndReplaceAgreeOnEmojiMatch() {
        // 不能出现「计数 1 处，却一处都没改」
        let texts = ["👍🏽"]
        XCTAssertEqual(ParagraphMatcher.countMatches(in: texts, find: "👍", options: options), 1)
        XCTAssertEqual(ParagraphMatcher.replace(in: texts, find: "👍", replaceWith: "X", options: options),
                       [ParagraphMatcher.Edit(textIndex: 0, newText: "X🏽")])
    }

    func testEmptyRunInsideMatchProducesNoSpuriousEdit() {
        let edits = ParagraphMatcher.replace(in: ["A", "", "B"], find: "AB", replaceWith: "X", options: options)
        XCTAssertEqual(edits, [ParagraphMatcher.Edit(textIndex: 0, newText: "X"),
                               ParagraphMatcher.Edit(textIndex: 2, newText: "")])
    }

    func testWholeWordRejectsMatchAfterNonBMPLetter() {
        let opts = ReplaceOptions(caseSensitive: true, wholeWord: true)
        XCTAssertEqual(ParagraphMatcher.countMatches(in: ["𝒜cat"], find: "cat", options: opts), 0)
        XCTAssertTrue(ParagraphMatcher.replace(in: ["𝒜cat"], find: "cat", replaceWith: "X",
                                               options: opts).isEmpty)
        // CJK 扩展 B 区字符同理
        XCTAssertEqual(ParagraphMatcher.countMatches(in: ["𠀀cat"], find: "cat", options: opts), 0)
        XCTAssertEqual(ParagraphMatcher.countMatches(in: ["cat𝒜"], find: "cat", options: opts), 0)
    }

    func testWholeWordAcceptsMatchBesideNonWordEmoji() {
        let opts = ReplaceOptions(caseSensitive: true, wholeWord: true)
        XCTAssertEqual(ParagraphMatcher.countMatches(in: ["👍cat"], find: "cat", options: opts), 1)
    }

    func testWholeWordTreatsComposedLetterAsWordCharacter() {
        let opts = ReplaceOptions(caseSensitive: true, wholeWord: true)
        XCTAssertEqual(ParagraphMatcher.countMatches(in: ["e\u{0301}cat"], find: "cat", options: opts), 0)
    }

    func testWholeWordTreatsDecimalDigitAsWordCharacter() {
        // 明确的取舍：十进制数字(Nd)算词字符；上标/罗马数字/分数(No/Nl，如 ①Ⅷ½)不算
        let opts = ReplaceOptions(caseSensitive: true, wholeWord: true)
        XCTAssertEqual(ParagraphMatcher.countMatches(in: ["1cat"], find: "cat", options: opts), 0)
        XCTAssertEqual(ParagraphMatcher.countMatches(in: ["①cat"], find: "cat", options: opts), 1)
    }
}
