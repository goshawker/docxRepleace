import Foundation

/// 界面语言。system = 跟随系统语言
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case zhHans
    case en

    var id: String { rawValue }

    /// 该语言用自身文字书写的名称（语言菜单里用它，便于辨认）；system 由词表提供
    var nativeName: String? {
        switch self {
        case .system: return nil
        case .zhHans: return "简体中文"
        case .en: return "English"
        }
    }

    /// 从系统偏好语言解析出实际语言（非 system 时返回自身）
    static func resolve(_ language: AppLanguage, preferred: [String]) -> AppLanguage {
        guard language == .system else { return language }
        let first = preferred.first?.lowercased() ?? "en"
        return first.hasPrefix("zh") ? .zhHans : .en
    }
}

/// 所有面向用户的文案。漏一条就编译不过 —— 这是刻意的。
/// 带插值的文案一律用函数，避免拼接时把语序写死。
protocol AppStrings: Sendable {
    // 应用与语言菜单
    var appTitle: String { get }
    var languageMenuLabel: String { get }      // 菜单的无障碍标签，如 "语言" / "Language"
    var followSystem: String { get }           // 菜单里 system 选项的显示名

    // 表单
    var folderLabel: String { get }
    var notSelected: String { get }
    var chooseButton: String { get }
    var findLabel: String { get }
    var findPlaceholder: String { get }
    var replaceLabel: String { get }
    var replacePlaceholder: String { get }
    var caseSensitiveToggle: String { get }
    var wholeWordToggle: String { get }
    var backupToggle: String { get }
    var scanButton: String { get }
    var replaceAllButton: String { get }
    var cancelButton: String { get }

    // 结果列表
    func matchCount(_ count: Int) -> String
    func overflowNotice(hiddenCount: Int) -> String
    var busyPlaceholder: String { get }
    var emptyResultsPlaceholder: String { get }

    // 状态栏
    var openBackupFolderButton: String { get }
    var revealInFinderButton: String { get }

    // 弹窗
    var confirmReplaceTitle: String { get }
    var startReplaceButton: String { get }
    func confirmReplaceMessage(fileCount: Int, totalMatches: Int) -> String
    var errorAlertTitle: String { get }
    var okButton: String { get }

    // 校验提示（六条）
    var validationNoFolder: String { get }
    var validationEmptyFind: String { get }
    var validationFindHasNewline: String { get }
    var validationReplaceHasNewline: String { get }
    var validationFindIllegalControlCharacter: String { get }
    var validationReplaceIllegalControlCharacter: String { get }

    // 文件夹选择面板
    var folderPanelPrompt: String { get }
    var folderPanelMessage: String { get }

    // 状态文本
    var statusInitial: String { get }
    func statusFolderSelected(path: String) -> String
    var statusScanning: String { get }
    func statusScanningProgress(completed: Int, total: Int) -> String
    var statusScanCancelled: String { get }
    var statusNoDocuments: String { get }
    var statusNoMatch: String { get }
    func statusScanSummary(matchedFiles: Int, totalMatches: Int) -> String
    var statusReplacing: String { get }
    func statusReplacingProgress(completed: Int, total: Int) -> String
    func replaceSummary(cancelled: Bool, modifiedFiles: Int, replacedCount: Int,
                        failedCount: Int, skippedCount: Int) -> String

    // 替换失败的弹窗
    func failedFilesAlertHeader(count: Int) -> String
    func failedFileLine(path: String, reason: String) -> String
    func failedFilesAlertMore(count: Int) -> String

    // Core / ZipError
    var zipNotAFile: String { get }
    var zip64Unsupported: String { get }
    func zipUnsupportedCompression(method: UInt16) -> String
    func zipEncryptedEntry(name: String) -> String
    func zipCorruptEntry(name: String) -> String
    func zipCRCMismatch(name: String) -> String
    func zipImplausibleSize(name: String) -> String
    var zipArchiveTooLarge: String { get }

    // Core / DocxXmlError
    func xmlParseFailed(detail: String) -> String
    func xmlNodeCountMismatch(dom: Int, raw: Int) -> String

    // Core / ReplaceCoordinator
    func backupDirectoryFailed(detail: String) -> String
    var fileNotWritable: String { get }
    var diskNoMatch: String { get }
    func backupFailed(detail: String) -> String
    var legacyDocument: String { get }
    func partMessage(part: String, message: String) -> String
}

struct ChineseStrings: AppStrings {
    var appTitle: String { "Word 批量查找替换" }
    var languageMenuLabel: String { "语言" }
    var followSystem: String { "跟随系统" }

    var folderLabel: String { "文件夹" }
    var notSelected: String { "未选择" }
    var chooseButton: String { "选择…" }
    var findLabel: String { "查找" }
    var findPlaceholder: String { "要查找的文字" }
    var replaceLabel: String { "替换为" }
    var replacePlaceholder: String { "替换成什么（可留空表示删除）" }
    var caseSensitiveToggle: String { "区分大小写" }
    var wholeWordToggle: String { "全字匹配" }
    var backupToggle: String { "替换前备份" }
    var scanButton: String { "扫描" }
    var replaceAllButton: String { "全部替换" }
    var cancelButton: String { "取消" }

    func matchCount(_ count: Int) -> String { "\(count) 处" }
    func overflowNotice(hiddenCount: Int) -> String { "…另有 \(hiddenCount) 处未显示" }
    var busyPlaceholder: String { "处理中…" }
    var emptyResultsPlaceholder: String { "扫描结果会显示在这里" }

    var openBackupFolderButton: String { "打开备份文件夹" }
    var revealInFinderButton: String { "在访达中显示" }

    var confirmReplaceTitle: String { "确认替换" }
    var startReplaceButton: String { "开始替换" }
    func confirmReplaceMessage(fileCount: Int, totalMatches: Int) -> String {
        "将修改 \(fileCount) 个文件，共 \(totalMatches) 处。是否继续？"
    }
    var errorAlertTitle: String { "出错了" }
    var okButton: String { "好" }

    var validationNoFolder: String { "请先选择文件夹" }
    var validationEmptyFind: String { "请输入要查找的内容" }
    var validationFindHasNewline: String { "查找内容不能包含换行符" }
    var validationReplaceHasNewline: String { "替换内容不能包含换行符" }
    var validationFindIllegalControlCharacter: String { "查找内容包含无法写入文档的控制字符" }
    var validationReplaceIllegalControlCharacter: String { "替换内容包含无法写入文档的控制字符" }

    var folderPanelPrompt: String { "选择" }
    var folderPanelMessage: String { "选择要处理的文件夹" }

    var statusInitial: String { "选择文件夹并输入查找内容" }
    func statusFolderSelected(path: String) -> String { "已选择：\(path)" }
    var statusScanning: String { "正在扫描…" }
    func statusScanningProgress(completed: Int, total: Int) -> String { "正在扫描 \(completed)/\(total)…" }
    var statusScanCancelled: String { "已取消扫描" }
    var statusNoDocuments: String { "文件夹中没有 .docx 或 .doc 文件" }
    var statusNoMatch: String { "没有找到匹配内容" }
    func statusScanSummary(matchedFiles: Int, totalMatches: Int) -> String {
        "\(matchedFiles) 个文件命中，共 \(totalMatches) 处"
    }
    var statusReplacing: String { "正在替换…" }
    func statusReplacingProgress(completed: Int, total: Int) -> String { "正在处理 \(completed)/\(total)" }
    func replaceSummary(cancelled: Bool, modifiedFiles: Int, replacedCount: Int,
                        failedCount: Int, skippedCount: Int) -> String {
        var summary = cancelled ? "已取消。" : ""
        summary += "完成：修改 \(modifiedFiles) 个文件，共替换 \(replacedCount) 处"
        if failedCount > 0 { summary += "；\(failedCount) 个文件失败" }
        if skippedCount > 0 { summary += "；\(skippedCount) 个文件已无匹配" }
        return summary
    }

    func failedFilesAlertHeader(count: Int) -> String { "\(count) 个文件未处理：" }
    func failedFileLine(path: String, reason: String) -> String { "\(path)：\(reason)" }
    func failedFilesAlertMore(count: Int) -> String { "\n…另有 \(count) 个" }

    var zipNotAFile: String { "不是有效的 .docx 文件（可能是 .doc 或已损坏）" }
    var zip64Unsupported: String { "ZIP64 格式暂不支持" }
    func zipUnsupportedCompression(method: UInt16) -> String { "不支持的压缩方式（\(method)）" }
    func zipEncryptedEntry(name: String) -> String { "文档已加密，无法读取（\(name)）" }
    func zipCorruptEntry(name: String) -> String { "文件结构损坏（\(name)）" }
    func zipCRCMismatch(name: String) -> String { "数据校验失败（\(name)）" }
    func zipImplausibleSize(name: String) -> String { "部件尺寸异常，已跳过（\(name)）" }
    var zipArchiveTooLarge: String { "文档过大，超出 ZIP 格式上限" }

    func xmlParseFailed(detail: String) -> String { "XML 解析失败：\(detail)" }
    func xmlNodeCountMismatch(dom: Int, raw: Int) -> String { "文档结构异常（DOM \(dom) / 原始 \(raw)）" }

    func backupDirectoryFailed(detail: String) -> String { "无法创建备份目录，已中止：\(detail)" }
    var fileNotWritable: String { "文件不可写，已跳过" }
    var diskNoMatch: String { "磁盘内容已无匹配" }
    func backupFailed(detail: String) -> String { "备份失败，已跳过：\(detail)" }
    var legacyDocument: String { "旧版 .doc 需先转为 .docx" }
    func partMessage(part: String, message: String) -> String { "\(part)：\(message)" }
}

struct EnglishStrings: AppStrings {
    var appTitle: String { "Word Batch Find & Replace" }
    var languageMenuLabel: String { "Language" }
    var followSystem: String { "Follow System" }

    var folderLabel: String { "Folder" }
    var notSelected: String { "Not selected" }
    var chooseButton: String { "Choose…" }
    var findLabel: String { "Find" }
    var findPlaceholder: String { "Text to find" }
    var replaceLabel: String { "Replace with" }
    var replacePlaceholder: String { "Replacement text (leave empty to delete)" }
    var caseSensitiveToggle: String { "Case sensitive" }
    var wholeWordToggle: String { "Whole words" }
    var backupToggle: String { "Back up before replacing" }
    var scanButton: String { "Scan" }
    var replaceAllButton: String { "Replace All" }
    var cancelButton: String { "Cancel" }

    func matchCount(_ count: Int) -> String { "\(count) match\(count == 1 ? "" : "es")" }
    func overflowNotice(hiddenCount: Int) -> String {
        "…and \(hiddenCount) more not shown"
    }
    var busyPlaceholder: String { "Working…" }
    var emptyResultsPlaceholder: String { "Scan results will appear here" }

    var openBackupFolderButton: String { "Open Backup Folder" }
    var revealInFinderButton: String { "Reveal in Finder" }

    var confirmReplaceTitle: String { "Confirm Replace" }
    var startReplaceButton: String { "Start Replacing" }
    func confirmReplaceMessage(fileCount: Int, totalMatches: Int) -> String {
        let files = "\(fileCount) file\(fileCount == 1 ? "" : "s")"
        let matches = "\(totalMatches) match\(totalMatches == 1 ? "" : "es")"
        return "This will modify \(files) with \(matches) in total. Continue?"
    }
    var errorAlertTitle: String { "Error" }
    var okButton: String { "OK" }

    var validationNoFolder: String { "Choose a folder first" }
    var validationEmptyFind: String { "Enter the text to find" }
    var validationFindHasNewline: String { "The find text cannot contain line breaks" }
    var validationReplaceHasNewline: String { "The replacement text cannot contain line breaks" }
    var validationFindIllegalControlCharacter: String {
        "The find text contains control characters that cannot be written to a document"
    }
    var validationReplaceIllegalControlCharacter: String {
        "The replacement text contains control characters that cannot be written to a document"
    }

    var folderPanelPrompt: String { "Choose" }
    var folderPanelMessage: String { "Choose the folder to process" }

    var statusInitial: String { "Choose a folder and enter text to find" }
    func statusFolderSelected(path: String) -> String { "Selected: \(path)" }
    var statusScanning: String { "Scanning…" }
    func statusScanningProgress(completed: Int, total: Int) -> String { "Scanning \(completed)/\(total)…" }
    var statusScanCancelled: String { "Scan cancelled" }
    var statusNoDocuments: String { "No .docx or .doc files in this folder" }
    var statusNoMatch: String { "No matches found" }
    func statusScanSummary(matchedFiles: Int, totalMatches: Int) -> String {
        let files = "\(matchedFiles) file\(matchedFiles == 1 ? "" : "s")"
        let matches = "\(totalMatches) match\(totalMatches == 1 ? "" : "es")"
        return "\(files) matched, \(matches) in total"
    }
    var statusReplacing: String { "Replacing…" }
    func statusReplacingProgress(completed: Int, total: Int) -> String { "Processing \(completed)/\(total)" }
    func replaceSummary(cancelled: Bool, modifiedFiles: Int, replacedCount: Int,
                        failedCount: Int, skippedCount: Int) -> String {
        var summary = cancelled ? "Cancelled. " : ""
        let files = "\(modifiedFiles) file\(modifiedFiles == 1 ? "" : "s")"
        let replacements = "\(replacedCount) replacement\(replacedCount == 1 ? "" : "s")"
        summary += "Done: \(files) modified, \(replacements) made"
        if failedCount > 0 { summary += "; \(failedCount) file\(failedCount == 1 ? "" : "s") failed" }
        if skippedCount > 0 {
            summary += "; \(skippedCount) file\(skippedCount == 1 ? "" : "s") had no remaining matches"
        }
        return summary
    }

    func failedFilesAlertHeader(count: Int) -> String {
        "\(count) file\(count == 1 ? "" : "s") not processed:"
    }
    func failedFileLine(path: String, reason: String) -> String { "\(path): \(reason)" }
    func failedFilesAlertMore(count: Int) -> String { "\n…and \(count) more" }

    var zipNotAFile: String { "Not a valid .docx file (possibly .doc or corrupted)" }
    var zip64Unsupported: String { "ZIP64 archives are not supported yet" }
    func zipUnsupportedCompression(method: UInt16) -> String {
        "Unsupported compression method (\(method))"
    }
    func zipEncryptedEntry(name: String) -> String { "Document is encrypted and cannot be read (\(name))" }
    func zipCorruptEntry(name: String) -> String { "Corrupt file structure (\(name))" }
    func zipCRCMismatch(name: String) -> String { "Data checksum mismatch (\(name))" }
    func zipImplausibleSize(name: String) -> String { "Implausible part size, skipped (\(name))" }
    var zipArchiveTooLarge: String { "Document is too large for the ZIP format limit" }

    func xmlParseFailed(detail: String) -> String { "XML parsing failed: \(detail)" }
    func xmlNodeCountMismatch(dom: Int, raw: Int) -> String {
        "Corrupt document structure (DOM \(dom) / raw \(raw))"
    }

    func backupDirectoryFailed(detail: String) -> String {
        "Could not create backup directory, aborted: \(detail)"
    }
    var fileNotWritable: String { "File is not writable, skipped" }
    var diskNoMatch: String { "No remaining matches on disk" }
    func backupFailed(detail: String) -> String { "Backup failed, skipped: \(detail)" }
    var legacyDocument: String { "Legacy .doc files must be converted to .docx first" }
    func partMessage(part: String, message: String) -> String { "\(part): \(message)" }
}

/// 全局语言状态。切换 language 后界面立即重绘
@MainActor
final class Localization: ObservableObject {
    static let shared = Localization()

    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Self.defaultsKey) }
    }

    private static let defaultsKey = "appLanguage"

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.defaultsKey)
        language = saved.flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    var effectiveLanguage: AppLanguage {
        AppLanguage.resolve(language, preferred: Locale.preferredLanguages)
    }

    var strings: AppStrings {
        effectiveLanguage == .en ? EnglishStrings() : ChineseStrings()
    }
}
