import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppViewModel()
    @StateObject private var localization = Localization.shared

    private var strings: AppStrings { localization.strings }

    var body: some View {
        VStack(spacing: 0) {
            form
            Divider()
            resultList
            Divider()
            statusBar
        }
        .alert(strings.confirmReplaceTitle, isPresented: $model.showReplaceConfirmation) {
            Button(strings.cancelButton, role: .cancel) {}
            Button(strings.startReplaceButton) { model.confirmReplace() }
        } message: {
            Text(strings.confirmReplaceMessage(fileCount: model.matchedItems.count,
                                               totalMatches: model.totalMatches))
        }
        .alert(strings.errorAlertTitle, isPresented: Binding(get: { model.alertMessage != nil },
                                                             set: { if !$0 { model.alertMessage = nil } })) {
            Button(strings.okButton, role: .cancel) {}
        } message: {
            Text(model.alertMessage ?? "")
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(strings.folderLabel).frame(width: 56, alignment: .trailing)
                Text(model.folderURL?.path ?? strings.notSelected)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(model.folderURL == nil ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(strings.chooseButton) { model.chooseFolder() }
                    .disabled(model.isBusy)
                languageMenu
            }
            HStack {
                Text(strings.findLabel).frame(width: 56, alignment: .trailing)
                TextField(strings.findPlaceholder, text: $model.findText)
            }
            HStack {
                Text(strings.replaceLabel).frame(width: 56, alignment: .trailing)
                TextField(strings.replacePlaceholder, text: $model.replaceText)
            }
            HStack(spacing: 16) {
                Spacer().frame(width: 56)
                Toggle(strings.caseSensitiveToggle, isOn: $model.caseSensitive)
                Toggle(strings.wholeWordToggle, isOn: $model.wholeWord)
                Toggle(strings.backupToggle, isOn: $model.backupEnabled)
            }
            HStack(spacing: 12) {
                Spacer().frame(width: 56)
                Button(strings.scanButton) { model.scan() }
                    .disabled(!model.canScan)
                Button(strings.replaceAllButton) { model.requestReplace() }
                    .disabled(!model.canReplace)
                if model.isBusy {
                    Button(strings.cancelButton) { model.cancel() }
                }
                if let message = model.validationMessage, !model.isBusy {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
    }

    private var languageMenu: some View {
        Menu {
            Picker("", selection: $localization.language) {
                Text(strings.followSystem).tag(AppLanguage.system)
                ForEach(AppLanguage.allCases.filter { $0 != .system }) { lang in
                    Text(lang.nativeName ?? lang.rawValue).tag(lang)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "globe")
        }
        .accessibilityLabel(strings.languageMenuLabel)
    }

    private var resultList: some View {
        List(model.results) { result in
            if result.previews.isEmpty {
                resultRow(result)
            } else {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(result.previews.enumerated()), id: \.offset) { _, preview in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preview.part)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                (Text(preview.before)
                                    + Text(preview.match).foregroundColor(.accentColor).bold()
                                    + Text(preview.after))
                                    .font(.callout)
                                    .textSelection(.enabled)
                            }
                        }
                        if result.matchCount > result.previews.count {
                            Text(strings.overflowNotice(hiddenCount: result.matchCount - result.previews.count))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } label: {
                    resultRow(result)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if model.results.isEmpty {
                Text(model.isBusy ? strings.busyPlaceholder : strings.emptyResultsPlaceholder)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func resultRow(_ result: FileScanResult) -> some View {
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
                    Button(strings.openBackupFolderButton) { model.openBackupFolder() }
                }
                if model.folderURL != nil {
                    Button(strings.revealInFinderButton) { model.revealFolder() }
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
        case .matched(let count): return strings.matchCount(count)
        case .noMatch: return strings.matchCount(0)
        case .unsupported(let reason): return reason
        case .failed(let reason): return reason
        }
    }
}
