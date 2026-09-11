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
    static func build(_ entries: [ZipOutputEntry]) -> Data {
        var out = Data()
        var central = Data()
        for entry in entries {
            let nameBytes = Array(entry.name.utf8)
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
