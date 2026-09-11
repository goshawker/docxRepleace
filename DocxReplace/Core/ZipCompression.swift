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

    /// raw DEFLATE 解压。expectedSize 来自 ZIP 中央目录。
    ///
    /// 关键：`compression_decode_buffer` 在缓冲区不足时**不报错**，而是返回已解出的
    /// 字节数（即截断）。因此初始容量取 `expectedSize + 1`，并且只接受「未填满缓冲区」
    /// 的结果——否则会把截断的数据当作完整结果返回。
    static func inflate(_ data: Data, expectedSize: Int) -> Data? {
        guard !data.isEmpty else { return expectedSize == 0 ? Data() : nil }
        guard expectedSize > 0 else { return nil }
        var capacity = expectedSize + 1
        for _ in 0..<5 {
            var output = Data(count: capacity)
            let written = output.withUnsafeMutableBytes { dst -> Int in
                guard let dstBase = dst.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return data.withUnsafeBytes { src -> Int in
                    guard let srcBase = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                    return compression_decode_buffer(dstBase, capacity, srcBase, data.count, nil, COMPRESSION_ZLIB)
                }
            }
            if written > 0, written < capacity {
                output.removeSubrange(written...)
                return output
            }
            capacity = capacity * 4 + 64
        }
        return nil
    }
}
