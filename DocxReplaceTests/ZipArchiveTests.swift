import XCTest
@testable import DocxReplace

final class ZipArchiveTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ZipArchiveTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// 用系统 textutil 生成真实 docx
    static func makeRealDocx(text: String, into directory: URL) throws -> URL {
        let htmlURL = directory.appendingPathComponent("source.html")
        let docxURL = directory.appendingPathComponent("source.docx")
        // 必须声明 charset：textutil 的 HTML 解析器在无 charset 时按系统编码（如 GBK）解读，
        // 会把 UTF-8 写入的中文变成乱码，导致 docx 里根本没有原始文字
        try "<html><head><meta charset=\"utf-8\"></head><body><p>\(text)</p></body></html>"
            .write(to: htmlURL, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        process.arguments = ["-convert", "docx", "-output", docxURL.path, htmlURL.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "textutil 生成 docx 失败")
        return docxURL
    }

    func testReadsRealDocx() throws {
        let url = try Self.makeRealDocx(text: "示例文档内容", into: tempDir)
        let archive = try ZipArchive(data: Data(contentsOf: url))
        let entry = try XCTUnwrap(archive.entry(named: "word/document.xml"))
        let xml = try archive.contents(of: entry)
        let text = String(decoding: xml, as: UTF8.self)
        XCTAssertTrue(text.contains("示例文档内容"), "应能解出正文文字")
    }

    func testStoredEntryRoundTrip() throws {
        let payload = Data("stored payload 内容".utf8)
        let entry = ZipOutputEntry(name: "a.txt", dosTime: 0, dosDate: 0, method: 0,
                                   crc32: ZipCRC32.checksum(payload),
                                   uncompressedSize: UInt32(payload.count),
                                   externalAttributes: 0, compressedData: payload)
        let archive = try ZipArchive(data: try ZipWriter.build([entry]))
        XCTAssertEqual(try archive.contents(of: try XCTUnwrap(archive.entry(named: "a.txt"))), payload)
    }

    func testDeflatedEntryRoundTrip() throws {
        let payload = Data(String(repeating: "hello world 你好 ", count: 200).utf8)
        let compressed = try XCTUnwrap(ZipCompression.deflate(payload))
        let entry = ZipOutputEntry(name: "dir/b.txt", dosTime: 0, dosDate: 0, method: 8,
                                   crc32: ZipCRC32.checksum(payload),
                                   uncompressedSize: UInt32(payload.count),
                                   externalAttributes: 0, compressedData: compressed)
        let archive = try ZipArchive(data: try ZipWriter.build([entry]))
        XCTAssertEqual(try archive.contents(of: try XCTUnwrap(archive.entry(named: "dir/b.txt"))), payload)
    }

    func testRejectsNonZipData() {
        XCTAssertThrowsError(try ZipArchive(data: Data(repeating: 0x41, count: 200)))
    }

    func testDetectsCRCMismatch() throws {
        let payload = Data("hello".utf8)
        let entry = ZipOutputEntry(name: "c.txt", dosTime: 0, dosDate: 0, method: 0,
                                   crc32: 0xDEADBEEF, uncompressedSize: UInt32(payload.count),
                                   externalAttributes: 0, compressedData: payload)
        let archive = try ZipArchive(data: try ZipWriter.build([entry]))
        XCTAssertThrowsError(try archive.contents(of: try XCTUnwrap(archive.entry(named: "c.txt"))))
    }

    func testMakeEntryChoosesDeflateWhenSmaller() {
        let compressible = Data(String(repeating: "abcabcabc", count: 100).utf8)
        let entry = ZipWriter.makeEntry(name: "x.xml", contents: compressible, date: Date())
        XCTAssertEqual(entry.method, 8)
        XCTAssertEqual(entry.uncompressedSize, UInt32(compressible.count))
        XCTAssertLessThan(entry.compressedData.count, compressible.count)
    }

    func testMakeEntryChoosesStoredWhenDeflateLarger() {
        var bytes = [UInt8]()
        var seed: UInt32 = 999
        for _ in 0..<64 {
            seed = seed &* 1664525 &+ 1013904223
            bytes.append(UInt8(truncatingIfNeeded: seed >> 16))
        }
        let incompressible = Data(bytes)
        let entry = ZipWriter.makeEntry(name: "y.bin", contents: incompressible, date: Date())
        XCTAssertEqual(entry.method, 0)
        XCTAssertEqual(entry.compressedData, incompressible)
    }

    func testCopiedEntryKeepsRawCompressedBytes() throws {
        let url = try Self.makeRealDocx(text: "原始内容", into: tempDir)
        let original = try ZipArchive(data: Data(contentsOf: url))
        let target = try XCTUnwrap(original.entry(named: "word/document.xml"))
        let rawBefore = try original.rawData(of: target)

        let outputs = try original.entries.map { entry -> ZipOutputEntry in
            ZipWriter.copyEntry(entry, raw: try original.rawData(of: entry))
        }
        let rebuilt = try ZipArchive(data: try ZipWriter.build(outputs))
        let targetAfter = try XCTUnwrap(rebuilt.entry(named: "word/document.xml"))
        XCTAssertEqual(try rebuilt.rawData(of: targetAfter), rawBefore, "未改动条目必须字节级一致")
    }

    func testSystemUnzipAcceptsOurArchive() throws {
        let payload = Data(String(repeating: "内容 content ", count: 100).utf8)
        let entries = [
            ZipWriter.makeEntry(name: "hello.txt", contents: payload, date: Date()),
            ZipWriter.makeEntry(name: "dir/world.xml", contents: Data("<a>1</a>".utf8), date: Date()),
        ]
        let zipURL = tempDir.appendingPathComponent("out.zip")
        try ZipWriter.build(entries).write(to: zipURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-t", zipURL.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, "系统 unzip 应能读取我们写出的 zip：\(output)")
    }

    /// 中央目录声称解压后有 4 GB，必须在申请内存之前拒绝
    func testRejectsImplausibleUncompressedSize() throws {
        let payload = Data("small".utf8)
        let compressed = try XCTUnwrap(ZipCompression.deflate(payload))
        let entry = ZipOutputEntry(name: "bomb.xml", dosTime: 0, dosDate: 0, method: 8,
                                   crc32: ZipCRC32.checksum(payload),
                                   uncompressedSize: 0xFFFFFFFE,
                                   externalAttributes: 0, compressedData: compressed)
        let archive = try ZipArchive(data: try ZipWriter.build([entry]))
        let target = try XCTUnwrap(archive.entry(named: "bomb.xml"))
        XCTAssertThrowsError(try archive.contents(of: target)) { error in
            XCTAssertEqual(error as? ZipError, .implausibleSize("bomb.xml"))
        }
    }

    func testBuildRejectsOversizedEntryCount() {
        let entries = (0...Int(UInt16.max)).map { index in
            ZipOutputEntry(name: "f\(index)", dosTime: 0, dosDate: 0, method: 0, crc32: 0,
                           uncompressedSize: 0, externalAttributes: 0, compressedData: Data())
        }
        XCTAssertThrowsError(try ZipWriter.build(entries)) { error in
            XCTAssertEqual(error as? ZipError, .archiveTooLarge)
        }
    }

    func testRejectsUnsupportedCompressionMethod() throws {
        let entry = ZipOutputEntry(name: "m12.bin", dosTime: 0, dosDate: 0, method: 12, crc32: 0,
                                   uncompressedSize: 0, externalAttributes: 0, compressedData: Data([1, 2, 3]))
        let archive = try ZipArchive(data: try ZipWriter.build([entry]))
        let target = try XCTUnwrap(archive.entry(named: "m12.bin"))
        XCTAssertThrowsError(try archive.contents(of: target)) { error in
            XCTAssertEqual(error as? ZipError, .unsupportedCompression(12))
        }
    }

    func testRejectsEncryptedEntry() throws {
        let payload = Data("secret".utf8)
        // 手工置位加密标志（bit 0）：本地头 flag 在偏移 6；
        // 解析用的 flags 来自中央目录，其条目 flag 位于 cdOffset + 8
        //（EOCD 位于最后 22 字节，cdOffset 在 EOCD 偏移 16 处），必须从布局计算而非硬编码。
        var bytes = [UInt8](try ZipWriter.build([ZipOutputEntry(name: "e.txt", dosTime: 0, dosDate: 0, method: 0,
                                                                crc32: ZipCRC32.checksum(payload),
                                                                uncompressedSize: UInt32(payload.count),
                                                                externalAttributes: 0, compressedData: payload)]))
        bytes[6] |= 0x01
        let eocd = bytes.count - 22
        let cdOffset = Int(ZipArchive.readU32(bytes, eocd + 16))
        bytes[cdOffset + 8] |= 0x01
        let archive = try ZipArchive(data: Data(bytes))
        let target = try XCTUnwrap(archive.entry(named: "e.txt"))
        XCTAssertThrowsError(try archive.contents(of: target)) { error in
            XCTAssertEqual(error as? ZipError, .encryptedEntry("e.txt"))
        }
    }

    func testEmptyArchiveHasNoEntries() throws {
        let archive = try ZipArchive(data: try ZipWriter.build([]))
        XCTAssertTrue(archive.entries.isEmpty)
        XCTAssertNil(archive.entry(named: "anything"))
    }

    /// 手工构造带 data descriptor（标志位 3）的归档：本地头里的 crc/尺寸为 0，
    /// 真实值写在数据之后的描述符里，中央目录才是权威来源
    func testReadsEntryWithDataDescriptor() throws {
        let payload = Data("descriptor payload 内容".utf8)
        let compressed = try XCTUnwrap(ZipCompression.deflate(payload))
        let crc = ZipCRC32.checksum(payload)
        let name = Array("dd.txt".utf8)

        var out = Data()
        appendLE32(&out, 0x04034b50)
        appendLE16(&out, 20)
        appendLE16(&out, 0x0008)
        appendLE16(&out, 8)
        appendLE16(&out, 0); appendLE16(&out, 0)
        appendLE32(&out, 0)
        appendLE32(&out, 0); appendLE32(&out, 0)
        appendLE16(&out, UInt16(name.count)); appendLE16(&out, 0)
        out.append(contentsOf: name)
        out.append(compressed)
        appendLE32(&out, 0x08074b50)
        appendLE32(&out, crc)
        appendLE32(&out, UInt32(compressed.count))
        appendLE32(&out, UInt32(payload.count))

        let cdOffset = UInt32(out.count)
        appendLE32(&out, 0x02014b50)
        appendLE16(&out, 20); appendLE16(&out, 20)
        appendLE16(&out, 0x0008)
        appendLE16(&out, 8)
        appendLE16(&out, 0); appendLE16(&out, 0)
        appendLE32(&out, crc)
        appendLE32(&out, UInt32(compressed.count))
        appendLE32(&out, UInt32(payload.count))
        appendLE16(&out, UInt16(name.count)); appendLE16(&out, 0); appendLE16(&out, 0)
        appendLE16(&out, 0); appendLE16(&out, 0)
        appendLE32(&out, 0)
        appendLE32(&out, 0)
        out.append(contentsOf: name)
        let cdSize = UInt32(out.count) - cdOffset

        appendLE32(&out, 0x06054b50)
        appendLE16(&out, 0); appendLE16(&out, 0)
        appendLE16(&out, 1); appendLE16(&out, 1)
        appendLE32(&out, cdSize); appendLE32(&out, cdOffset)
        appendLE16(&out, 0)

        let archive = try ZipArchive(data: out)
        let entry = try XCTUnwrap(archive.entry(named: "dd.txt"))
        XCTAssertEqual(try archive.contents(of: entry), payload)
        XCTAssertEqual(try archive.rawData(of: entry), compressed, "描述符不得混进原始压缩字节")
    }
}

private func appendLE16(_ data: inout Data, _ value: UInt16) {
    data.append(UInt8(value & 0xFF))
    data.append(UInt8((value >> 8) & 0xFF))
}

private func appendLE32(_ data: inout Data, _ value: UInt32) {
    data.append(UInt8(value & 0xFF))
    data.append(UInt8((value >> 8) & 0xFF))
    data.append(UInt8((value >> 16) & 0xFF))
    data.append(UInt8((value >> 24) & 0xFF))
}
