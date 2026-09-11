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
}
