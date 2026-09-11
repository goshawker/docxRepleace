import Foundation

enum ZipError: Error, Equatable {
    case notAZipFile
    case zip64Unsupported
    case unsupportedCompression(UInt16)
    case encryptedEntry(String)
    case corruptEntry(String)
    case crcMismatch(String)
    case implausibleSize(String)
    case archiveTooLarge

    var message: String {
        switch self {
        case .notAZipFile: return "不是有效的 .docx 文件（可能是 .doc 或已损坏）"
        case .zip64Unsupported: return "ZIP64 格式暂不支持"
        case .unsupportedCompression(let method): return "不支持的压缩方式（\(method)）"
        case .encryptedEntry(let name): return "文档已加密，无法读取（\(name)）"
        case .corruptEntry(let name): return "文件结构损坏（\(name)）"
        case .crcMismatch(let name): return "数据校验失败（\(name)）"
        case .implausibleSize(let name): return "部件尺寸异常，已跳过（\(name)）"
        case .archiveTooLarge: return "文档过大，超出 ZIP 格式上限"
        }
    }
}

struct ZipEntry: Equatable {
    var name: String
    var versionMadeBy: UInt16
    var flags: UInt16
    var method: UInt16
    var modTime: UInt16
    var modDate: UInt16
    var crc32: UInt32
    var compressedSize: UInt32
    var uncompressedSize: UInt32
    var externalAttributes: UInt32
    var localHeaderOffset: UInt32
}

struct ZipArchive {
    let entries: [ZipEntry]
    private let bytes: [UInt8]

    init(data: Data) throws {
        let bytes = [UInt8](data)
        self.bytes = bytes
        guard bytes.count >= 22 else { throw ZipError.notAZipFile }

        var eocd = -1
        let minStart = max(0, bytes.count - 65557)
        var i = bytes.count - 22
        while i >= minStart {
            if Self.readU32(bytes, i) == 0x06054b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.notAZipFile }

        let totalEntries = Int(Self.readU16(bytes, eocd + 10))
        let cdSize = Int(Self.readU32(bytes, eocd + 12))
        let cdOffset = Int(Self.readU32(bytes, eocd + 16))
        if totalEntries == 0xFFFF || cdSize == 0xFFFFFFFF || cdOffset == 0xFFFFFFFF {
            throw ZipError.zip64Unsupported
        }
        guard cdOffset >= 0, cdSize >= 0, cdOffset + cdSize <= bytes.count else {
            throw ZipError.corruptEntry("中央目录越界")
        }

        var parsed: [ZipEntry] = []
        var p = cdOffset
        for _ in 0..<totalEntries {
            guard p + 46 <= bytes.count, Self.readU32(bytes, p) == 0x02014b50 else {
                throw ZipError.corruptEntry("中央目录条目损坏")
            }
            let flags = Self.readU16(bytes, p + 8)
            let method = Self.readU16(bytes, p + 10)
            let crc = Self.readU32(bytes, p + 16)
            let compressedSize = Self.readU32(bytes, p + 20)
            let uncompressedSize = Self.readU32(bytes, p + 24)
            let nameLen = Int(Self.readU16(bytes, p + 28))
            let extraLen = Int(Self.readU16(bytes, p + 30))
            let commentLen = Int(Self.readU16(bytes, p + 32))
            let localOffset = Self.readU32(bytes, p + 42)
            guard p + 46 + nameLen + extraLen + commentLen <= bytes.count else {
                throw ZipError.corruptEntry("中央目录条目越界")
            }
            if compressedSize == 0xFFFFFFFF || uncompressedSize == 0xFFFFFFFF || localOffset == 0xFFFFFFFF {
                throw ZipError.zip64Unsupported
            }
            let name = String(decoding: bytes[(p + 46)..<(p + 46 + nameLen)], as: UTF8.self)
            parsed.append(ZipEntry(name: name,
                                   versionMadeBy: Self.readU16(bytes, p + 4),
                                   flags: flags,
                                   method: method,
                                   modTime: Self.readU16(bytes, p + 12),
                                   modDate: Self.readU16(bytes, p + 14),
                                   crc32: crc,
                                   compressedSize: compressedSize,
                                   uncompressedSize: uncompressedSize,
                                   externalAttributes: Self.readU32(bytes, p + 38),
                                   localHeaderOffset: localOffset))
            p += 46 + nameLen + extraLen + commentLen
        }
        self.entries = parsed
    }

    func entry(named name: String) -> ZipEntry? {
        entries.first { $0.name == name }
    }

    /// 未解压的原始压缩字节（用于原样拷贝）
    func rawData(of entry: ZipEntry) throws -> Data {
        if entry.flags & 0x0001 != 0 { throw ZipError.encryptedEntry(entry.name) }
        let base = Int(entry.localHeaderOffset)
        guard base + 30 <= bytes.count, Self.readU32(bytes, base) == 0x04034b50 else {
            throw ZipError.corruptEntry(entry.name)
        }
        let nameLen = Int(Self.readU16(bytes, base + 26))
        let extraLen = Int(Self.readU16(bytes, base + 28))
        let start = base + 30 + nameLen + extraLen
        let end = start + Int(entry.compressedSize)
        guard start >= 0, end <= bytes.count else { throw ZipError.corruptEntry(entry.name) }
        return Data(bytes[start..<end])
    }

    func contents(of entry: ZipEntry) throws -> Data {
        if entry.flags & 0x0001 != 0 { throw ZipError.encryptedEntry(entry.name) }
        let raw = try rawData(of: entry)
        let out: Data
        switch entry.method {
        case 0:
            out = raw
        case 8:
            guard Int(entry.uncompressedSize) <= Self.inflateLimit(compressedSize: entry.compressedSize) else {
                throw ZipError.implausibleSize(entry.name)
            }
            guard let inflated = ZipCompression.inflate(raw, expectedSize: Int(entry.uncompressedSize)) else {
                throw ZipError.corruptEntry(entry.name)
            }
            out = inflated
        default:
            throw ZipError.unsupportedCompression(entry.method)
        }
        guard ZipCRC32.checksum(out) == entry.crc32 else {
            throw ZipError.crcMismatch(entry.name)
        }
        return out
    }

    /// 解压尺寸上限：至少 64 MiB，或压缩数据的 256 倍。
    /// 防止损坏或恶意的 uncompressedSize 触发失控的内存分配。
    private static func inflateLimit(compressedSize: UInt32) -> Int {
        max(64 * 1024 * 1024, Int(compressedSize) * 256)
    }

    static func readU16(_ b: [UInt8], _ o: Int) -> UInt16 {
        UInt16(b[o]) | (UInt16(b[o + 1]) << 8)
    }

    static func readU32(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(b[o]) | (UInt32(b[o + 1]) << 8) | (UInt32(b[o + 2]) << 16) | (UInt32(b[o + 3]) << 24)
    }
}
