import RuleBoxCore
import SwiftUI

struct MainWorkspaceView: View {
    @Bindable var store: RuleBoxStore

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 220, ideal: 244, max: 280)
        } detail: {
            Group {
                switch store.selection {
                case .folder(let folderID):
                    if let folder = store.workspace.folders.first(where: { $0.id == folderID }) {
                        HSplitView {
                            RuleListView(store: store, folder: folder)
                                .frame(minWidth: 300, idealWidth: 336, maxWidth: 390)

                            if let rule = store.selectedRule, folder.rules.contains(where: { $0.id == rule.id }) {
                                RuleEditorView(store: store, folder: folder, rule: rule)
                                    .frame(minWidth: 540, maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                emptyRuleSelectionView(folder: folder)
                                    .frame(minWidth: 540, maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                    } else {
                        ContentUnavailableView("No Folder Selected", systemImage: "folder")
                    }
                case .presets:
                    PresetsGalleryView(store: store)
                case .activity:
                    ActivityLogView(store: store)
                case nil:
                    ContentUnavailableView("Select a Watched Folder", systemImage: "tray.full")
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(store.workspace.watcherActive ? Color.green : Color.secondary.opacity(0.45))
                        .frame(width: 8, height: 8)
                    Text(store.workspace.watcherActive ? "Live Watcher" : "Paused")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.55), in: Capsule())
                .onTapGesture {
                    store.toggleWatcher()
                }
                .help("Click to pause or resume background folder watching")
            }

            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(store.totalPendingMatches > 0 ? Color.accentColor : Color.green)
                    Text("\(store.totalPendingMatches) pending match\(store.totalPendingMatches == 1 ? "" : "es") · \(store.statusMessage)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.45), in: Capsule())
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    store.refreshAllPreviews()
                } label: {
                    Label("Refresh Preview", systemImage: "arrow.clockwise")
                }
                .help("Re-scan folders and update dry-run match counts (⌘⇧R)")

                Button {
                    if let folder = store.selectedFolder {
                        store.runFolderNow(id: folder.id)
                    } else {
                        store.runAllFoldersNow()
                    }
                } label: {
                    Label("Run Rules", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .help("Execute matching rules on the selected folder (⌘R)")
            }
        }
    }

    private func emptyRuleSelectionView(folder: WatchedFolder) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text("No Rule Selected")
                .font(.title3.weight(.semibold))
            Text("Select a rule for \"\(folder.name)\" or create a new one to see live before/after file previews.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            Button("New Rule") {
                store.addNewRule(to: folder.id)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
