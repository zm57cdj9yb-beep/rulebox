import RuleBoxCore
import SwiftUI

struct RuleEditorView: View {
    @Bindable var store: RuleBoxStore
    let folder: WatchedFolder
    let rule: AutomationRule

    private func mutate(_ transform: (inout AutomationRule) -> Void) {
        var copy = rule
        transform(&copy)
        store.updateRule(copy, in: folder.id)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(spacing: 12) {
                    TextField("Rule Name", text: Binding(
                        get: { rule.name },
                        set: { val in mutate { $0.name = val } }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .semibold))

                    Toggle("Enabled", isOn: Binding(
                        get: { rule.isEnabled },
                        set: { val in mutate { $0.isEnabled = val } }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                // 1. Conditions Card
                editorSectionCard(
                    title: "Conditions",
                    subtitle: "Evaluate files inside \(folder.name)",
                    trailing: {
                        HStack(spacing: 6) {
                            Text("Match")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                            Picker("", selection: Binding(
                                get: { rule.matchMode },
                                set: { val in mutate { $0.matchMode = val } }
                            )) {
                                ForEach(MatchMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 78)
                            .controlSize(.small)
                        }
                    }
                ) {
                    VStack(spacing: 8) {
                        ForEach(Array(rule.conditions.enumerated()), id: \.element.id) { idx, cond in
                            conditionRow(cond: cond, index: idx)
                        }

                        HStack {
                            Button {
                                mutate { $0.conditions.append(RuleCondition(field: .name, op: .contains, value: "")) }
                            } label: {
                                Label("Add Condition", systemImage: "plus.circle")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .buttonStyle(.borderless)
                            Spacer()
                        }
                        .padding(.top, 2)
                    }
                }

                // 2. Actions Card
                editorSectionCard(
                    title: "Actions",
                    subtitle: "Executed in order when a file matches",
                    trailing: {
                        Toggle("Stop after match", isOn: Binding(
                            get: { rule.stopProcessingMoreRules },
                            set: { val in mutate { $0.stopProcessingMoreRules = val } }
                        ))
                        .controlSize(.small)
                        .font(.system(size: 11.5))
                    }
                ) {
                    VStack(spacing: 10) {
                        ForEach(Array(rule.actions.enumerated()), id: \.element.id) { idx, action in
                            actionRow(action: action, index: idx)
                        }

                        HStack {
                            Menu {
                                ForEach(ActionKind.allCases) { kind in
                                    Button {
                                        mutate { $0.actions.append(RuleAction(kind: kind)) }
                                    } label: {
                                        Label(kind.rawValue, systemImage: kind.symbolName)
                                    }
                                }
                            } label: {
                                Label("Add Action", systemImage: "plus.circle")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            Spacer()
                        }
                        .padding(.top, 2)
                    }
                }

                // 3. Live Dry-Run Match Preview Card
                editorSectionCard(
                    title: "Live Dry-Run Preview",
                    subtitle: "Exact before -> after simulation on real files (zero files modified)",
                    trailing: {
                        Text("\(store.selectedRulePreview.count) matching file\(store.selectedRulePreview.count == 1 ? "" : "s")")
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(store.selectedRulePreview.isEmpty ? Color.secondary : Color.accentColor)
                    }
                ) {
                    if store.selectedRulePreview.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            Text("No files in \(folder.name) currently match these conditions.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(store.selectedRulePreview.enumerated()), id: \.element.id) { idx, match in
                                if idx > 0 { Divider() }
                                HStack(spacing: 10) {
                                    Image(systemName: iconForKind(match.fileKind))
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 18)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(match.sourceFileName)
                                            .font(.system(size: 12, weight: .medium))
                                            .lineLimit(1)
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrow.turn.down.right")
                                                .font(.system(size: 9.5))
                                                .foregroundStyle(.secondary)
                                            Text(match.predictedDisplayDestination)
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundStyle(match.willTrash ? Color.red : Color.accentColor)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                                .layoutPriority(1)
                                        }
                                    }
                                    .layoutPriority(1)

                                    Spacer(minLength: 8)

                                    HStack(spacing: 4) {
                                        ForEach(match.actionBadges, id: \.self) { badge in
                                            Text(badge)
                                                .font(.system(size: 10, weight: .semibold))
                                                .fixedSize()
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(
                                                    badge == "Trash"
                                                        ? Color.red.opacity(0.14)
                                                        : Color.accentColor.opacity(0.12),
                                                    in: Capsule()
                                                )
                                                .foregroundStyle(badge == "Trash" ? Color.red : Color.accentColor)
                                        }
                                    }
                                    .fixedSize()

                                    Text(formatBytes(match.fileSizeBytes))
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 56, alignment: .trailing)
                                }
                                .padding(.vertical, 7)
                            }
                        }
                    }
                }
            }
            .padding(18)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Condition Row

    @ViewBuilder
    private func conditionRow(cond: RuleCondition, index: Int) -> some View {
        HStack(spacing: 8) {
            Picker("", selection: Binding(
                get: { cond.field },
                set: { newField in
                    mutate {
                        $0.conditions[index].field = newField
                        if !newField.supportedOperators.contains($0.conditions[index].op) {
                            $0.conditions[index].op = newField.defaultOperator
                        }
                        if newField == .kind && $0.conditions[index].value.isEmpty {
                            $0.conditions[index].value = FileKindCategory.pdf.rawValue
                        } else if newField == .finderTag && $0.conditions[index].value.isEmpty {
                            $0.conditions[index].value = FinderTagColor.blue.rawValue
                        }
                    }
                }
            )) {
                ForEach(ConditionField.allCases) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .labelsHidden()
            .frame(width: 142)
            .controlSize(.small)

            Picker("", selection: Binding(
                get: { cond.op },
                set: { newOp in mutate { $0.conditions[index].op = newOp } }
            )) {
                ForEach(cond.field.supportedOperators) { op in
                    Text(op.rawValue).tag(op)
                }
            }
            .labelsHidden()
            .frame(width: 126)
            .controlSize(.small)

            if cond.field == .kind {
                Picker("", selection: Binding(
                    get: { cond.value },
                    set: { val in mutate { $0.conditions[index].value = val } }
                )) {
                    ForEach(FileKindCategory.allCases) { k in
                        Text(k.rawValue).tag(k.rawValue)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
            } else if cond.field == .finderTag {
                Picker("", selection: Binding(
                    get: { cond.value },
                    set: { val in mutate { $0.conditions[index].value = val } }
                )) {
                    ForEach(FinderTagColor.allCases) { c in
                        Text(c.rawValue).tag(c.rawValue)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
            } else if cond.field != .isHidden {
                TextField(placeholderFor(cond.field), text: Binding(
                    get: { cond.value },
                    set: { val in mutate { $0.conditions[index].value = val } }
                ))
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
            } else {
                Spacer()
            }

            Button {
                mutate { $0.conditions.remove(at: index) }
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(rule.conditions.count <= 1)
        }
    }

    // MARK: - Action Row

    @ViewBuilder
    private func actionRow(action: RuleAction, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Picker("", selection: Binding(
                    get: { action.kind },
                    set: { newKind in mutate { $0.actions[index].kind = newKind } }
                )) {
                    ForEach(ActionKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .labelsHidden()
                .frame(width: 162)
                .controlSize(.small)

                switch action.kind {
                case .move, .copy:
                    Button {
                        if let picked = pickDestinationFolder(initialPath: action.targetPath) {
                            mutate { $0.actions[index].targetPath = picked }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.accentColor)
                            Text(abbreviateFolderDisplay(action.targetPath))
                                .font(.system(size: 12))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text("Choose…")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.8), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(action.targetPath.isEmpty ? "Select destination folder" : action.targetPath)

                case .rename, .sortIntoSubfolder:
                    TextField(
                        action.kind == .rename ? "[Year]-[Month]_[Name].[Ext]" : "[Year]/[Month]",
                        text: Binding(
                            get: { action.pattern },
                            set: { val in mutate { $0.actions[index].pattern = val } }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)

                case .addTag:
                    Picker("", selection: Binding(
                        get: { action.tagName },
                        set: { val in mutate { $0.actions[index].tagName = val } }
                    )) {
                        ForEach(FinderTagColor.allCases) { color in
                            Text(color.rawValue).tag(color.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                    .controlSize(.small)
                    Spacer()

                case .runShellScript:
                    TextField("e.g. open -a Preview \"$1\"", text: Binding(
                        get: { action.script },
                        set: { val in mutate { $0.actions[index].script = val } }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11.5, design: .monospaced))
                    .controlSize(.small)

                case .removeTags, .archiveZip, .moveToTrash:
                    Spacer()
                }

                Button {
                    mutate { $0.actions.remove(at: index) }
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .disabled(rule.actions.count <= 1)
            }

            if action.kind == .rename || action.kind == .sortIntoSubfolder {
                HStack(spacing: 5) {
                    Text("Tokens:")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                    ForEach(["[Name]", "[Ext]", "[Year]", "[Month]", "[Date]", "[Counter]"], id: \.self) { tok in
                        Button(tok) {
                            mutate { $0.actions[index].pattern.append(tok) }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .fixedSize()
                        .padding(.horizontal, 5.5)
                        .padding(.vertical, 2.5)
                        .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(Color.accentColor)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 8)
            }
        }
    }

    // MARK: - Helpers

    private func editorSectionCard<Trailing: View, Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                trailing()
            }

            Divider()

            content()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1)
        )
    }

    private func placeholderFor(_ field: ConditionField) -> String {
        switch field {
        case .name: return "e.g. Screenshot"
        case .fileExtension: return "e.g. zip,tar,gz"
        case .sizeMB: return "e.g. 500"
        case .ageDays: return "e.g. 14"
        case .contents: return "e.g. Invoice"
        default: return ""
        }
    }

    private func iconForKind(_ kind: FileKindCategory) -> String {
        switch kind {
        case .pdf: return "doc.richtext"
        case .image: return "photo"
        case .archive: return "archivebox"
        case .diskImage: return "externaldrive"
        case .video: return "film"
        case .audio: return "music.note"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .document: return "doc.text"
        case .folder: return "folder"
        case .other: return "doc"
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func abbreviateFolderDisplay(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Choose destination folder…" }
        let url = URL(fileURLWithPath: trimmed)
        let parent = url.deletingLastPathComponent().lastPathComponent
        let leaf = url.lastPathComponent
        if parent.isEmpty || parent == "/" { return leaf }
        return "\(parent) / \(leaf)"
    }
}
