import XCTest
@testable import DocxReplace

final class SanityTests: XCTestCase {
    func testModuleLoads() {
        XCTAssertFalse(ReplaceOptions().caseSensitive)
        XCTAssertTrue(ReplaceOptions(caseSensitive: true, wholeWord: true).wholeWord)
    }
}
