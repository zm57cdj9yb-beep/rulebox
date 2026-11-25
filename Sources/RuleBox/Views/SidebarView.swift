import RuleBoxCore
import SwiftUI

struct SidebarView: View {
    @Bindable var store: RuleBoxStore

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $store.selection) {
                Section("Watched Folders") {
                    ForEach(store.workspace.folders) { folder in
                        let pending = (store.dryRunByFolder[folder.id] ?? []).count
                        let isSelected = store.selection == .folder(folder.id)
                        HStack(spacing: 8) {
                            Image(systemName: folder.iconName)
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(isSelected ? Color.white : (folder.isEnabled ? Color.accentColor : Color.secondary))
                                .frame(width: 18)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(folder.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)
                                Text("\(folder.rules.filter(\.isEnabled).count) active rule\(folder.rules.filter(\.isEnabled).count == 1 ? "" : "s")")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
                            }

                            Spacer(minLength: 4)

                            if pending > 0 {
                                Text("\(pending)")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6.5)
                                    .padding(.vertical, 1.5)
                                    .background(isSelected ? Color.white.opacity(0.26) : Color.accentColor, in: Capsule())
                            }
                        }
                        .padding(.vertical, 2)
                        .tag(RuleBoxStore.SidebarDestination.folder(folder.id))
                        .contextMenu {
                            Button("Run Rules Now") {
                                store.runFolderNow(id: folder.id)
                            }
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
                            }
                            Divider()
                            Button("Remove Folder", role: .destructive) {
                                store.removeFolder(id: folder.id)
                            }
                        }
                    }
                }

                Section("Workspace") {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles.rectangle.stack")
                            .font(.system(size: 13.5))
                            .foregroundStyle(.orange)
                            .frame(width: 18)
                        Text("Rule Presets")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .tag(RuleBoxStore.SidebarDestination.presets)

                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 13.5))
                            .foregroundStyle(.green)
                            .frame(width: 18)
                        Text("Activity & Undo")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        if !store.activity.isEmpty {
                            Text("\(store.activity.count)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(RuleBoxStore.SidebarDestination.activity)
                }
            }
            .listStyle(.sidebar)
            .onChange(of: store.selection) { _, newValue in
                if case .folder(let id) = newValue,
                   let folder = store.workspace.folders.first(where: { $0.id == id }) {
                    if !folder.rules.contains(where: { $0.id == store.selectedRuleID }) {
                        store.selectedRuleID = folder.rules.first?.id
                    }
                    store.refreshSelectedRulePreview()
                }
            }

            Divider()

            HStack(spacing: 8) {
                Button {
                    pickFolderAndAdd(store: store)
                } label: {
                    Label("Add Folder", systemImage: "folder.badge.plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderless)

                Spacer()

                Button {
                    store.resetDemoFiles()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11.5))
                }
                .buttonStyle(.borderless)
                .help("Restore Demo Sample Files")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
    }
}
