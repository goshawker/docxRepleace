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

struct FileScanResult: Identifiable, Equatable {
    var item: ScanItem
    var outcome: FileOutcome

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
