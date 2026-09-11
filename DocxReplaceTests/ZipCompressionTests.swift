import XCTest
@testable import DocxReplace

final class ZipCompressionTests: XCTestCase {
    func testCRC32KnownVector() {
        // "123456789" 的 CRC32 标准值
        XCTAssertEqual(ZipCRC32.checksum(Data("123456789".utf8)), 0xCBF43926)
    }

    func testCRC32OfEmptyData() {
        XCTAssertEqual(ZipCRC32.checksum(Data()), 0)
    }

    func testDeflateThenInflateRoundTrip() throws {
        let original = Data(String(repeating: "测试 abcdefg 12345 ", count: 500).utf8)
        let deflated = try XCTUnwrap(ZipCompression.deflate(original))
        XCTAssertLessThan(deflated.count, original.count)
        let inflated = try XCTUnwrap(ZipCompression.inflate(deflated, expectedSize: original.count))
        XCTAssertEqual(inflated, original)
    }

    func testInflateIncompressibleData() throws {
        var bytes = [UInt8]()
        var seed: UInt32 = 12345
        for _ in 0..<4096 {
            seed = seed &* 1664525 &+ 1013904223
            bytes.append(UInt8(truncatingIfNeeded: seed >> 16))
        }
        let original = Data(bytes)
        let deflated = try XCTUnwrap(ZipCompression.deflate(original))
        let inflated = try XCTUnwrap(ZipCompression.inflate(deflated, expectedSize: original.count))
        XCTAssertEqual(inflated, original)
    }

    func testInflateRejectsGarbage() {
        let garbage = Data([0x01, 0x02, 0x03, 0x04, 0x05])
        XCTAssertNil(ZipCompression.inflate(garbage, expectedSize: 100))
    }
}
