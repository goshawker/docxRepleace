import Foundation

struct ZipOutputEntry {
    var name: String
    var dosTime: UInt16
    var dosDate: UInt16
    var method: UInt16
    var crc32: UInt32
    var uncompressedSize: UInt32
    var externalAttributes: UInt32
    var compressedData: Data
}

enum ZipWriter {
    static func build(_ entries: [ZipOutputEntry]) throws -> Data {
        // EOCD 用 0xFFFF 表示 zip64 哨兵，65535 条会被读取器判为 zip64 而拒绝，
        // 因此上限必须严格小于 UInt16.max
        guard entries.count < Int(UInt16.max) else { throw ZipError.archiveTooLarge }
        var out = Data()
        var central = Data()
        for entry in entries {
            guard out.count < Int(UInt32.max) else { throw ZipError.archiveTooLarge }
            let nameBytes = Array(entry.name.utf8)
            guard nameBytes.count <= Int(UInt16.max) else { throw ZipError.archiveTooLarge }
            // 尺寸字段是 UInt32：超出即会静默截断成错误偏移，必须响亮失败
            guard entry.compressedData.count < Int(UInt32.max) else { throw ZipError.archiveTooLarge }
            let offset = UInt32(out.count)
            let flags: UInt16 = nameBytes.contains { $0 >= 0x80 } ? 0x0800 : 0

            appendU32(&out, 0x04034b50)
            appendU16(&out, 20)
            appendU16(&out, flags)
            appendU16(&out, entry.method)
            appendU16(&out, entry.dosTime)
            appendU16(&out, entry.dosDate)
            appendU32(&out, entry.crc32)
            appendU32(&out, UInt32(entry.compressedData.count))
            appendU32(&out, entry.uncompressedSize)
            appendU16(&out, UInt16(nameBytes.count))
            appendU16(&out, 0)
            out.append(contentsOf: nameBytes)
            out.append(entry.compressedData)

            appendU32(&central, 0x02014b50)
            appendU16(&central, 20)
            appendU16(&central, 20)
            appendU16(&central, flags)
            appendU16(&central, entry.method)
            appendU16(&central, entry.dosTime)
            appendU16(&central, entry.dosDate)
            appendU32(&central, entry.crc32)
            appendU32(&central, UInt32(entry.compressedData.count))
            appendU32(&central, entry.uncompressedSize)
            appendU16(&central, UInt16(nameBytes.count))
            appendU16(&central, 0)
            appendU16(&central, 0)
            appendU16(&central, 0)
            appendU16(&central, 0)
            appendU32(&central, entry.externalAttributes)
            appendU32(&central, offset)
            central.append(contentsOf: nameBytes)
        }
        guard out.count < Int(UInt32.max) else { throw ZipError.archiveTooLarge }
        guard central.count < Int(UInt32.max) else { throw ZipError.archiveTooLarge }
        let cdOffset = UInt32(out.count)
        out.append(central)

        appendU32(&out, 0x06054b50)
        appendU16(&out, 0)
        appendU16(&out, 0)
        appendU16(&out, UInt16(entries.count))
        appendU16(&out, UInt16(entries.count))
        appendU32(&out, UInt32(central.count))
        appendU32(&out, cdOffset)
        appendU16(&out, 0)
        return out
    }

    /// 用未压缩内容构造条目，自动选择 deflate 或 stored
    static func makeEntry(name: String, contents: Data, date: Date,
                          externalAttributes: UInt32 = 0) -> ZipOutputEntry {
        let (dosTime, dosDate) = dosDateTime(from: date)
        let crc = ZipCRC32.checksum(contents)
        // 上限与读取器的 inflateLimit 保持一致：否则写出的归档会被我们自己判为
        // implausibleSize 而无法回读，此时退回 stored
        if let deflated = ZipCompression.deflate(contents), deflated.count < contents.count, !contents.isEmpty,
           contents.count <= max(64 * 1024 * 1024, deflated.count * 256) {
            return ZipOutputEntry(name: name, dosTime: dosTime, dosDate: dosDate, method: 8,
                                  crc32: crc, uncompressedSize: UInt32(contents.count),
                                  externalAttributes: externalAttributes, compressedData: deflated)
        }
        return ZipOutputEntry(name: name, dosTime: dosTime, dosDate: dosDate, method: 0,
                              crc32: crc, uncompressedSize: UInt32(contents.count),
                              externalAttributes: externalAttributes, compressedData: contents)
    }

    /// 原样拷贝一个条目（保留原始压缩字节与元数据）
    static func copyEntry(_ entry: ZipEntry, raw: Data) -> ZipOutputEntry {
        ZipOutputEntry(name: entry.name, dosTime: entry.modTime, dosDate: entry.modDate,
                       method: entry.method, crc32: entry.crc32,
                       uncompressedSize: entry.uncompressedSize,
                       externalAttributes: entry.externalAttributes, compressedData: raw)
    }

    static func dosDateTime(from date: Date) -> (time: UInt16, date: UInt16) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = max(1980, c.year ?? 1980)
        let dosDate = UInt16((((year - 1980) & 0x7F) << 9) | ((c.month ?? 1) << 5) | (c.day ?? 1))
        let dosTime = UInt16(((c.hour ?? 0) << 11) | ((c.minute ?? 0) << 5) | ((c.second ?? 0) / 2))
        return (dosTime, dosDate)
    }

    private static func appendU16(_ data: inout Data, _ value: UInt16) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
    }

    private static func appendU32(_ data: inout Data, _ value: UInt32) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }
}
