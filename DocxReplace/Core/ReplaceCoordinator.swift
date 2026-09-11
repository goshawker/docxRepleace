import Foundation

struct ScanProgress: Equatable {
    var completed: Int
    var total: Int
}

struct ReplaceProgress: Equatable {
    var completed: Int
    var total: Int
    var currentPath: String
}

enum ReplaceCoordinator {
    /// 并行扫描（并发上限为 CPU 核数），返回按路径排序的结果
    static func scan(folder: URL, find: String, options: ReplaceOptions,
                     onProgress: @escaping (ScanProgress) -> Void) async -> [FileScanResult] {
        let items = FileScanner.scan(folder: folder)
        let total = items.count
        guard total > 0 else {
            onProgress(ScanProgress(completed: 0, total: 0))
            return []
        }

        var collected: [FileScanResult?] = Array(repeating: nil, count: total)
        var completed = 0
        await withTaskGroup(of: (Int, FileScanResult).self) { group in
            let limit = max(2, ProcessInfo.processInfo.activeProcessorCount)
            var next = 0
            while next < min(limit, total) {
                let index = next
                group.addTask { (index, analyze(items[index], find: find, options: options)) }
                next += 1
            }
            while let (index, result) = await group.next() {
                collected[index] = result
                completed += 1
                onProgress(ScanProgress(completed: completed, total: total))
                if next < total {
                    let pending = next
                    group.addTask { (pending, analyze(items[pending], find: find, options: options)) }
                    next += 1
                }
            }
        }
        return collected.compactMap { $0 }
    }

    /// 串行替换；仅处理传入的条目。备份失败则跳过该文件
    static func replace(items: [ScanItem], sourceFolder: URL, find: String, replaceWith: String,
                        options: ReplaceOptions, backupEnabled: Bool, backupRoot: URL,
                        onProgress: @escaping (ReplaceProgress) -> Void) async -> ReplaceReport {
        var report = ReplaceReport()
        guard !items.isEmpty else { return report }

        var runDirectory: URL?
        if backupEnabled {
            do {
                runDirectory = try BackupManager.makeRunDirectory(root: backupRoot,
                                                                  sourceFolder: sourceFolder,
                                                                  date: Date())
                report.backupDirectory = runDirectory
            } catch {
                report.failed.append(ReportedFile(path: sourceFolder.lastPathComponent,
                                                  reason: "无法创建备份目录，已中止：\(error.localizedDescription)"))
                return report
            }
        }

        let total = items.count
        for (index, item) in items.enumerated() {
            if Task.isCancelled {
                report.cancelled = true
                break
            }
            onProgress(ReplaceProgress(completed: index, total: total, currentPath: item.relativePath))
            do {
                let data = try Data(contentsOf: item.url)
                let (newData, count) = try DocxTextReplacer.replace(docxData: data, find: find,
                                                                    replaceWith: replaceWith,
                                                                    options: options)
                guard count > 0 else { continue }
                if let runDirectory {
                    do {
                        try BackupManager.backup(fileURL: item.url, sourceFolder: sourceFolder,
                                                 runDirectory: runDirectory)
                    } catch {
                        report.failed.append(ReportedFile(path: item.relativePath,
                                                          reason: "备份失败，已跳过：\(error.localizedDescription)"))
                        continue
                    }
                }
                try newData.write(to: item.url, options: [.atomic])
                report.modifiedFiles += 1
                report.replacedCount += count
            } catch {
                report.failed.append(ReportedFile(path: item.relativePath,
                                                  reason: describe(error, in: try? Data(contentsOf: item.url))))
            }
        }
        onProgress(ReplaceProgress(completed: total, total: total, currentPath: ""))
        return report
    }

    private static func analyze(_ item: ScanItem, find: String, options: ReplaceOptions) -> FileScanResult {
        switch item.kind {
        case .legacyDoc:
            return FileScanResult(item: item, outcome: .unsupported("旧版 .doc 需先转为 .docx"))
        case .docx:
            do {
                let data = try Data(contentsOf: item.url)
                let count = try DocxTextReplacer.countMatches(docxData: data, find: find, options: options)
                return FileScanResult(item: item, outcome: count > 0 ? .matched(count) : .noMatch)
            } catch {
                return FileScanResult(item: item,
                                      outcome: .failed(describe(error, in: try? Data(contentsOf: item.url))))
            }
        }
    }

    static func describe(_ error: Error) -> String {
        if let zip = error as? ZipError { return zip.message }
        if let xml = error as? DocxXmlError { return xml.message }
        return error.localizedDescription
    }

    /// `DocxXmlError` 不带部件名（Task 10b 审查跟进）；组装提示时补上出错部件，便于定位。
    /// 解析类错误可按 targetPartNames 顺序复走一遍回溯；仅在错误路径调用，代价可忽略。
    /// 改写阶段的 `nodeCountMismatch` 无法以同样方式回溯，退回通用提示。
    private static func describe(_ error: Error, in data: Data?) -> String {
        if let xml = error as? DocxXmlError, let data, let part = failingPart(in: data) {
            return "\(part)：\(xml.message)"
        }
        return describe(error)
    }

    private static func failingPart(in data: Data) -> String? {
        guard let archive = try? ZipArchive(data: data),
              let names = try? DocxTextReplacer.targetPartNames(in: archive) else { return nil }
        for name in names {
            guard let entry = archive.entry(named: name),
                  let contents = try? archive.contents(of: entry) else { return name }
            if (try? DocxXmlAnalyzer.analyze([UInt8](contents))) == nil { return name }
        }
        return nil
    }
}
