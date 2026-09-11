import Foundation

enum BackupManager {
    /// 优先 App 所在文件夹；不可写或位于 DerivedData（Xcode 直接运行）时退回 ~/Documents
    static func defaultRoot() -> URL {
        let appFolder = Bundle.main.bundleURL.deletingLastPathComponent()
        if appFolder.path.contains("/DerivedData/")
            || !FileManager.default.isWritableFile(atPath: appFolder.path) {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
            return docs.appendingPathComponent("DocxReplace备份", isDirectory: true)
        }
        return appFolder
    }

    static func makeRunDirectory(root: URL, sourceFolder: URL, date: Date) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let run = root
            .appendingPathComponent("DocxReplace备份_\(formatter.string(from: date))", isDirectory: true)
            .appendingPathComponent(sourceFolder.lastPathComponent, isDirectory: true)
        try FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)
        return run
    }

    static func backup(fileURL: URL, sourceFolder: URL, runDirectory: URL) throws {
        let base = sourceFolder.standardizedFileURL.path
        let path = fileURL.standardizedFileURL.path
        let relative = path.hasPrefix(base + "/") ? String(path.dropFirst(base.count + 1)) : fileURL.lastPathComponent
        let destination = runDirectory.appendingPathComponent(relative)
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: fileURL, to: destination)
    }
}
