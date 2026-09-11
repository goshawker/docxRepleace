import Foundation

enum FileScanner {
    static func scan(folder: URL) -> [ScanItem] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: folder,
                                             includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                                             options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            return []
        }
        let basePath = folder.standardizedFileURL.path
        var items: [ScanItem] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if name.hasPrefix("~$") { continue }
            // 备份目录必须排除：应用若位于被扫描的文件夹内，备份就会落在扫描范围内，
            // 而备份保存的是替换前的旧文字 —— 不排除的话每轮扫描都会「重新找到」它们，
            // 替换永远做不完（反复扫描替换的真实原因）。
            if url.hasDirectoryPath, name.hasPrefix(BackupManager.directoryNamePrefix) {
                enumerator.skipDescendants()
                continue
            }
            let kind: FileKind
            switch url.pathExtension.lowercased() {
            case "docx": kind = .docx
            case "doc": kind = .legacyDoc
            default: continue
            }
            let path = url.standardizedFileURL.path
            let relative = path.hasPrefix(basePath + "/") ? String(path.dropFirst(basePath.count + 1)) : name
            items.append(ScanItem(url: url, relativePath: relative, kind: kind))
        }
        return items.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }
}
