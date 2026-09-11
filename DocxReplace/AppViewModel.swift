import AppKit
import Foundation

enum Phase: Equatable {
    case idle
    case scanning
    case scanned
    case replacing
    case finished
}

/// 状态栏文案的「语义值」：只存数据，渲染时才查当前语言的词表，
/// 这样切换语言后已显示的状态行也能立即跟着变
enum ViewStatus: Equatable {
    case initial
    case folderSelected(path: String)
    case scanning
    case scanningProgress(completed: Int, total: Int)
    case scanCancelled
    case noDocuments
    case noMatch
    case scanSummary(matchedFiles: Int, totalMatches: Int)
    case replacing
    case replacingProgress(completed: Int, total: Int)
    case replaceSummary(cancelled: Bool, modifiedFiles: Int, replacedCount: Int,
                        failedCount: Int, skippedCount: Int)

    func text(_ s: AppStrings) -> String {
        switch self {
        case .initial: return s.statusInitial
        case .folderSelected(let path): return s.statusFolderSelected(path: path)
        case .scanning: return s.statusScanning
        case .scanningProgress(let completed, let total):
            return s.statusScanningProgress(completed: completed, total: total)
        case .scanCancelled: return s.statusScanCancelled
        case .noDocuments: return s.statusNoDocuments
        case .noMatch: return s.statusNoMatch
        case .scanSummary(let matchedFiles, let totalMatches):
            return s.statusScanSummary(matchedFiles: matchedFiles, totalMatches: totalMatches)
        case .replacing: return s.statusReplacing
        case .replacingProgress(let completed, let total):
            return s.statusReplacingProgress(completed: completed, total: total)
        case .replaceSummary(let cancelled, let modifiedFiles, let replacedCount,
                             let failedCount, let skippedCount):
            return s.replaceSummary(cancelled: cancelled, modifiedFiles: modifiedFiles,
                                    replacedCount: replacedCount, failedCount: failedCount,
                                    skippedCount: skippedCount)
        }
    }
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
    @Published private(set) var status: ViewStatus = .initial
    @Published var progress: Double = 0
    @Published var currentFile = ""
    @Published var backupDirectory: URL?
    @Published var alertMessage: String?
    @Published var showReplaceConfirmation = false

    private var runningTask: Task<Void, Never>?
    private var scannedFolder: URL?

    /// 当前语言的词表。切换语言后 ContentView 会重绘，
    /// statusText / validationMessage 随之按新词表重新渲染
    var strings: AppStrings { Localization.shared.strings }

    var statusText: String { status.text(strings) }

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
        let s = strings
        if folderURL == nil { return s.validationNoFolder }
        if findText.isEmpty { return s.validationEmptyFind }
        if findText.contains("\n") || findText.contains("\r") { return s.validationFindHasNewline }
        if replaceText.contains("\n") || replaceText.contains("\r") { return s.validationReplaceHasNewline }
        if Self.hasIllegalControlCharacter(findText) { return s.validationFindIllegalControlCharacter }
        if Self.hasIllegalControlCharacter(replaceText) { return s.validationReplaceIllegalControlCharacter }
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
        let s = strings
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = s.folderPanelPrompt
        panel.message = s.folderPanelMessage
        guard panel.runModal() == .OK, let url = panel.url else { return }
        runningTask?.cancel()
        folderURL = url
        scannedFolder = nil
        results = []
        phase = .idle
        progress = 0
        currentFile = ""
        status = .folderSelected(path: url.path)
    }

    func scan() {
        guard let folder = folderURL, validationMessage == nil else { return }
        let find = findText
        let options = self.options
        let strings = self.strings
        phase = .scanning
        progress = 0
        currentFile = ""
        status = .scanning
        runningTask = Task { [weak self] in
            let results = await ReplaceCoordinator.scan(folder: folder, find: find, options: options,
                                                        strings: strings) { p in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.progress = p.total == 0 ? 1 : Double(p.completed) / Double(p.total)
                    self.status = .scanningProgress(completed: p.completed, total: p.total)
                }
            }
            guard let self else { return }
            guard !Task.isCancelled else {
                // 取消后必须复位，否则界面会永远卡在「扫描中」
                self.phase = .idle
                self.progress = 0
                self.status = .scanCancelled
                return
            }
            guard self.folderURL == folder else { return }   // 期间换过文件夹，丢弃这批结果
            self.results = results
            self.scannedFolder = folder
            self.phase = .scanned
            let matched = self.matchedItems.count
            self.progress = 1
            if results.isEmpty {
                self.status = .noDocuments
            } else if matched == 0 {
                self.status = .noMatch
            } else {
                self.status = .scanSummary(matchedFiles: matched, totalMatches: self.totalMatches)
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
        let strings = self.strings

        phase = .replacing
        progress = 0
        status = .replacing
        runningTask = Task { [weak self] in
            let report = await ReplaceCoordinator.replace(items: items, sourceFolder: folder,
                                                          find: find, replaceWith: replaceWith,
                                                          options: options, backupEnabled: backup,
                                                          backupRoot: backupRoot,
                                                          strings: strings) { p in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.progress = p.total == 0 ? 1 : Double(p.completed) / Double(p.total)
                    self.currentFile = p.currentPath
                    self.status = .replacingProgress(completed: p.completed, total: p.total)
                }
            }
            guard let self else { return }
            self.backupDirectory = report.backupDirectory
            self.phase = .finished
            self.progress = 1
            self.currentFile = ""
            let s = self.strings
            if !report.failed.isEmpty {
                let shown = report.failed.prefix(5)
                    .map { s.failedFileLine(path: $0.path, reason: $0.reason) }
                    .joined(separator: "\n")
                let more = report.failed.count > 5 ? s.failedFilesAlertMore(count: report.failed.count - 5) : ""
                self.alertMessage = s.failedFilesAlertHeader(count: report.failed.count) + "\n\(shown)\(more)"
            }
            self.status = .replaceSummary(cancelled: report.cancelled,
                                          modifiedFiles: report.modifiedFiles,
                                          replacedCount: report.replacedCount,
                                          failedCount: report.failed.count,
                                          skippedCount: report.skipped.count)
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
        let strings = self.strings
        phase = .scanning
        runningTask = Task { [weak self] in
            let results = await ReplaceCoordinator.scan(folder: folder, find: find, options: options,
                                                        strings: strings) { _ in }
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
