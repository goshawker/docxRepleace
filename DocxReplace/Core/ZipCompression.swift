import Compression
import Foundation

enum ZipCompression {
    /// raw DEFLATE 压缩；缓冲区不足时返回 nil（调用方应改为 stored 存储）
    static func deflate(_ data: Data) -> Data? {
        guard !data.isEmpty else { return Data() }
        let capacity = data.count + data.count / 1000 + 64
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { dst -> Int in
            guard let dstBase = dst.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return data.withUnsafeBytes { src -> Int in
                guard let srcBase = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_encode_buffer(dstBase, capacity, srcBase, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0, written < capacity else { return nil }
        output.removeSubrange(written...)
        return output
    }

    /// raw DEFLATE 解压。expectedSize 来自 ZIP 中央目录
    static func inflate(_ data: Data, expectedSize: Int) -> Data? {
        guard !data.isEmpty else { return expectedSize == 0 ? Data() : nil }
        guard expectedSize > 0 else { return nil }
        var capacity = expectedSize
        for _ in 0..<5 {
            var output = Data(count: capacity)
            let written = output.withUnsafeMutableBytes { dst -> Int in
                guard let dstBase = dst.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return data.withUnsafeBytes { src -> Int in
                    guard let srcBase = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                    return compression_decode_buffer(dstBase, capacity, srcBase, data.count, nil, COMPRESSION_ZLIB)
                }
            }
            if written > 0 {
                if written < capacity || written == expectedSize {
                    output.removeSubrange(written...)
                    return output
                }
            }
            capacity = capacity * 4 + 64
        }
        return nil
    }
}
