import Foundation

struct ReplaceOptions: Equatable {
    var caseSensitive: Bool = false
    var wholeWord: Bool = false
}

enum FileKind {
    case docx
    case legacyDoc
}

struct ScanItem: Equatable {
    var url: URL
    var relativePath: String
    var kind: FileKind
}

enum FileOutcome: Equatable {
    case matched(Int)
    case noMatch
    case unsupported(String)
    case failed(String)
}

/// 一处命中的上下文预览（前后各取若干字，便于用户确认到底命中了什么写法）
struct MatchPreview: Equatable {
    var part: String     // 部件名，如 "word/document.xml"
    var before: String   // 命中前的文字（被截断时以 "…" 开头）
    var match: String    // 实际命中的文字
    var after: String    // 命中后的文字（被截断时以 "…" 结尾）
}

struct FileScanResult: Identifiable, Equatable {
    var item: ScanItem
    var outcome: FileOutcome
    var previews: [MatchPreview] = []

    var id: String { item.relativePath }
    var relativePath: String { item.relativePath }

    var matchCount: Int {
        if case .matched(let count) = outcome { return count }
        return 0
    }
}

struct ReportedFile: Equatable {
    var path: String
    var reason: String
}

struct ReplaceReport: Equatable {
    var modifiedFiles: Int = 0
    var replacedCount: Int = 0
    var skipped: [ReportedFile] = []
    var failed: [ReportedFile] = []
    var backupDirectory: URL?
    var cancelled: Bool = false
}
