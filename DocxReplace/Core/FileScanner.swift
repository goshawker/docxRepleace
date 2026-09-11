import Foundation

enum FileScanner {
    static func scan(folder: URL) -> [ScanItem] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: folder,
                                             includingPropertiesForKeys: [.isRegularFileKey],
                                             options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            return []
        }
        let basePath = folder.standardizedFileURL.path
        var items: [ScanItem] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if name.hasPrefix("~$") { continue }
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
