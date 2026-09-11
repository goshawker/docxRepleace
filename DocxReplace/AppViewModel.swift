import AppKit
import Foundation

enum Phase: Equatable {
    case idle
    case scanning
    case scanned
    case replacing
    case finished
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var folderURL: URL?
    @Published var findText = ""
    @Published var replaceText = ""
    @Published var caseSensitive = false
    @Published var wholeWord = false
    @Published var backupEnabled = true
    @Published var phase: Phase = .idle
    @Published var results: [FileScanResult] = []
    @Published var statusText = "选择文件夹并输入查找内容"
    @Published var progress: Double = 0
    @Published var currentFile = ""
    @Published var backupDirectory: URL?
    @Published var alertMessage: String?
    @Published var showReplaceConfirmation = false

    private var runningTask: Task<Void, Never>?
    private var scannedFolder: URL?

    var options: ReplaceOptions {
        ReplaceOptions(caseSensitive: caseSensitive, wholeWord: wholeWord)
    }

    var matchedItems: [ScanItem] {
        results.compactMap { result in
            if case .matched = result.outcome { return result.item }
            return nil
        }
    }

    var totalMatches: Int {
        results.reduce(0) { $0 + $1.matchCount }
    }

    var validationMessage: String? {
        if folderURL == nil { return "请先选择文件夹" }
        if findText.isEmpty { return "请输入要查找的内容" }
        if findText.contains("\n") || findText.contains("\r") { return "查找内容不能包含换行符" }
        if replaceText.contains("\n") || replaceText.contains("\r") { return "替换内容不能包含换行符" }
        if Self.hasIllegalControlCharacter(findText) { return "查找内容包含无法写入文档的控制字符" }
        if Self.hasIllegalControlCharacter(replaceText) { return "替换内容包含无法写入文档的控制字符" }
        return nil
    }

    /// XML 1.0 不允许 C0 控制字符（\t 除外）与 U+FFFE/U+FFFF。
    /// 它们无法被转义成合法 XML，粘贴进来的话会让整份文件写出后无法解析。
    private static func hasIllegalControlCharacter(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            ($0.value < 0x20 && $0 != "\t") || $0.value == 0xFFFE || $0.value == 0xFFFF
        }
    }

    var isBusy: Bool { phase == .scanning || phase == .replacing }
    var canScan: Bool { validationMessage == nil && !isBusy }
    var canReplace: Bool { validationMessage == nil && !isBusy && !matchedItems.isEmpty }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.message = "选择要处理的文件夹"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        runningTask?.cancel()
        folderURL = url
        scannedFolder = nil
        results = []
        phase = .idle
        progress = 0
        currentFile = ""
        statusText = "已选择：\(url.path)"
    }

    func scan() {
        guard let folder = folderURL, validationMessage == nil else { return }
        let find = findText
        let options = self.options
        phase = .scanning
        progress = 0
        currentFile = ""
        statusText = "正在扫描…"
        runningTask = Task { [weak self] in
            let results = await ReplaceCoordinator.scan(folder: folder, find: find, options: options) { p in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.progress = p.total == 0 ? 1 : Double(p.completed) / Double(p.total)
                    self.statusText = "正在扫描 \(p.completed)/\(p.total)…"
                }
            }
            guard let self else { return }
            guard !Task.isCancelled else {
                // 取消后必须复位，否则界面会永远卡在「扫描中」
                self.phase = .idle
                self.progress = 0
                self.statusText = "已取消扫描"
                return
            }
            guard self.folderURL == folder else { return }   // 期间换过文件夹，丢弃这批结果
            self.results = results
            self.scannedFolder = folder
            self.phase = .scanned
            let matched = self.matchedItems.count
            self.progress = 1
            if results.isEmpty {
                self.statusText = "文件夹中没有 .docx 或 .doc 文件"
            } else if matched == 0 {
                self.statusText = "没有找到匹配内容"
            } else {
                self.statusText = "\(matched) 个文件命中，共 \(self.totalMatches) 处"
            }
        }
    }

    func requestReplace() {
        guard canReplace else { return }
        showReplaceConfirmation = true
    }

    func confirmReplace() {
        guard let folder = scannedFolder else { return }
        let find = findText
        let replaceWith = replaceText
        let options = self.options
        let items = matchedItems
        let backup = backupEnabled
        let backupRoot = BackupManager.defaultRoot()

        phase = .replacing
        progress = 0
        statusText = "正在替换…"
        runningTask = Task { [weak self] in
            let report = await ReplaceCoordinator.replace(items: items, sourceFolder: folder,
                                                          find: find, replaceWith: replaceWith,
                                                          options: options, backupEnabled: backup,
                                                          backupRoot: backupRoot) { p in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.progress = p.total == 0 ? 1 : Double(p.completed) / Double(p.total)
                    self.currentFile = p.currentPath
                    self.statusText = "正在处理 \(p.completed)/\(p.total)"
                }
            }
            guard let self else { return }
            self.backupDirectory = report.backupDirectory
            self.phase = .finished
            self.progress = 1
            self.currentFile = ""
            if !report.failed.isEmpty {
                let shown = report.failed.prefix(5).map { "\($0.path)：\($0.reason)" }.joined(separator: "\n")
                let more = report.failed.count > 5 ? "\n…另有 \(report.failed.count - 5) 个" : ""
                self.alertMessage = "\(report.failed.count) 个文件未处理：\n\(shown)\(more)"
            }
            var summary = report.cancelled ? "已取消。" : ""
            summary += "完成：修改 \(report.modifiedFiles) 个文件，共替换 \(report.replacedCount) 处"
            if !report.failed.isEmpty { summary += "；\(report.failed.count) 个文件失败" }
            if !report.skipped.isEmpty { summary += "；\(report.skipped.count) 个文件已无匹配" }
            self.statusText = summary
            self.rescanAfterReplace()
        }
    }

    func cancel() {
        runningTask?.cancel()
    }

    private func rescanAfterReplace() {
        guard let folder = scannedFolder else { return }
        let find = findText
        let options = self.options
        phase = .scanning
        runningTask = Task { [weak self] in
            let results = await ReplaceCoordinator.scan(folder: folder, find: find, options: options) { _ in }
            guard let self else { return }
            guard !Task.isCancelled else {
                // 这里也要复位，否则在「扫描中」取消会再次卡死界面
                self.phase = .finished
                return
            }
            self.results = results
            self.phase = .finished
        }
    }

    func openBackupFolder() {
        guard let url = backupDirectory else { return }
        NSWorkspace.shared.open(url)
    }

    func revealFolder() {
        guard let url = folderURL else { return }
        NSWorkspace.shared.open(url)
    }
}
