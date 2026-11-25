import RuleBoxCore
import SwiftUI

struct RuleListView: View {
    @Bindable var store: RuleBoxStore
    let folder: WatchedFolder

    var body: some View {
        VStack(spacing: 0) {
            // Folder Header
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center) {
                    Image(systemName: folder.iconName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    Text(folder.name)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Button {
                        store.addNewRule(to: folder.id)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("New Rule (⌘N)")
                }

                HStack(spacing: 6) {
                    Text(abbreviatePath(folder.path))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Toggle("Auto-Run", isOn: Binding(
                        get: { folder.autoRunOnChange },
                        set: { _ in store.toggleAutoRun(for: folder.id) }
                    ))
                    .toggleStyle(.checkbox)
                    .controlSize(.mini)
                    .font(.system(size: 11))
                    .help("Automatically execute matching rules when files are dropped into this folder")
                    Text("· \(store.fileCountByFolder[folder.id] ?? 0) files")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.65))

            Divider()

            if folder.rules.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checklist")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("No Rules Yet")
                        .font(.headline)
                    Text("Add a rule or pick a template from Rule Presets.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Add First Rule") {
                        store.addNewRule(to: folder.id)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(folder.rules) { rule in
                            RuleCardRow(
                                rule: rule,
                                matchCount: store.matchCount(for: rule.id, in: folder.id),
                                isSelected: store.selectedRuleID == rule.id,
                                onSelect: {
                                    store.selectedRuleID = rule.id
                                    store.refreshSelectedRulePreview()
                                },
                                onToggle: { enabled in
                                    var updated = rule
                                    updated.isEnabled = enabled
                                    store.updateRule(updated, in: folder.id)
                                },
                                onMoveUp: { store.moveRule(id: rule.id, in: folder.id, offset: -1) },
                                onMoveDown: { store.moveRule(id: rule.id, in: folder.id, offset: 1) },
                                onDuplicate: { store.duplicateRule(id: rule.id, in: folder.id) },
                                onDelete: { store.deleteRule(id: rule.id, from: folder.id) }
                            )
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func abbreviatePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

private struct RuleCardRow: View {
    let rule: AutomationRule
    let matchCount: Int
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggle: (Bool) -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Toggle("", isOn: Binding(get: { rule.isEnabled }, set: { onToggle($0) }))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()

                Text(rule.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(rule.isEnabled ? .primary : .secondary)
                    .lineLimit(1)

                Spacer()

                if matchCount > 0 {
                    Text("\(matchCount) match\(matchCount == 1 ? "" : "es")")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            isSelected ? Color.accentColor : Color.accentColor.opacity(0.14),
                            in: Capsule()
                        )
                } else {
                    Text("0 matches")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }

            if !rule.conditions.isEmpty {
                Text(rule.conditions.map(\.shortSummary).joined(separator: "  ·  "))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !rule.actions.isEmpty {
                HStack(spacing: 5) {
                    ForEach(rule.actions.prefix(3)) { action in
                        HStack(spacing: 3) {
                            Image(systemName: action.kind.symbolName)
                                .font(.system(size: 9.5))
                            Text(action.shortSummary)
                                .font(.system(size: 10.5, weight: .medium))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(
                            action.kind == .moveToTrash
                                ? Color.red.opacity(0.12)
                                : Color(nsColor: .quaternaryLabelColor).opacity(0.35),
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                        )
                        .foregroundStyle(action.kind == .moveToTrash ? Color.red : Color.primary.opacity(0.82))
                    }
                }
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.65),
                    lineWidth: isSelected ? 1.5 : 1
                )
        )
        .opacity(rule.isEnabled ? 1.0 : 0.62)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button("Move Up", action: onMoveUp)
            Button("Move Down", action: onMoveDown)
            Divider()
            Button("Duplicate Rule", action: onDuplicate)
            Button("Delete Rule", role: .destructive, action: onDelete)
        }
    }
}
