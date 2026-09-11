import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppViewModel()

    var body: some View {
        VStack(spacing: 0) {
            form
            Divider()
            resultList
            Divider()
            statusBar
        }
        .alert("确认替换", isPresented: $model.showReplaceConfirmation) {
            Button("取消", role: .cancel) {}
            Button("开始替换") { model.confirmReplace() }
        } message: {
            Text("将修改 \(model.matchedItems.count) 个文件，共 \(model.totalMatches) 处。是否继续？")
        }
        .alert("出错了", isPresented: Binding(get: { model.alertMessage != nil },
                                             set: { if !$0 { model.alertMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(model.alertMessage ?? "")
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("文件夹").frame(width: 56, alignment: .trailing)
                Text(model.folderURL?.path ?? "未选择")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(model.folderURL == nil ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("选择…") { model.chooseFolder() }
                    .disabled(model.isBusy)
            }
            HStack {
                Text("查找").frame(width: 56, alignment: .trailing)
                TextField("要查找的文字", text: $model.findText)
            }
            HStack {
                Text("替换为").frame(width: 56, alignment: .trailing)
                TextField("替换成什么（可留空表示删除）", text: $model.replaceText)
            }
            HStack(spacing: 16) {
                Spacer().frame(width: 56)
                Toggle("区分大小写", isOn: $model.caseSensitive)
                Toggle("全字匹配", isOn: $model.wholeWord)
                Toggle("替换前备份", isOn: $model.backupEnabled)
            }
            HStack(spacing: 12) {
                Spacer().frame(width: 56)
                Button("扫描") { model.scan() }
                    .disabled(!model.canScan)
                Button("全部替换") { model.requestReplace() }
                    .disabled(!model.canReplace)
                if model.isBusy {
                    Button("取消") { model.cancel() }
                }
                if let message = model.validationMessage, !model.isBusy {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
    }

    private var resultList: some View {
        List(model.results) { result in
            HStack(spacing: 8) {
                Image(systemName: icon(for: result.outcome))
                    .foregroundStyle(color(for: result.outcome))
                Text(result.relativePath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(detail(for: result.outcome))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .opacity(isDimmed(result.outcome) ? 0.55 : 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if model.results.isEmpty {
                Text(model.isBusy ? "处理中…" : "扫描结果会显示在这里")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusBar: some View {
        VStack(spacing: 6) {
            if model.isBusy {
                ProgressView(value: model.progress)
                    .progressViewStyle(.linear)
            }
            HStack {
                Text(model.statusText).font(.callout).lineLimit(2)
                Spacer()
                if let backup = model.backupDirectory {
                    Text(backup.path).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    Button("打开备份文件夹") { model.openBackupFolder() }
                }
                if model.folderURL != nil {
                    Button("在访达中显示") { model.revealFolder() }
                }
            }
        }
        .padding(10)
    }

    private func icon(for outcome: FileOutcome) -> String {
        switch outcome {
        case .matched: return "doc.text.fill"
        case .noMatch: return "doc.text"
        case .unsupported: return "exclamationmark.triangle"
        case .failed: return "xmark.octagon"
        }
    }

    private func color(for outcome: FileOutcome) -> Color {
        switch outcome {
        case .matched: return .accentColor
        case .noMatch: return .secondary
        case .unsupported: return .orange
        case .failed: return .red
        }
    }

    private func isDimmed(_ outcome: FileOutcome) -> Bool {
        if case .noMatch = outcome { return true }
        return false
    }

    private func detail(for outcome: FileOutcome) -> String {
        switch outcome {
        case .matched(let count): return "\(count) 处"
        case .noMatch: return "0 处"
        case .unsupported(let reason): return reason
        case .failed(let reason): return reason
        }
    }
}
