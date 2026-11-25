import RuleBoxCore
import SwiftUI

struct PresetsGalleryView: View {
    @Bindable var store: RuleBoxStore
    @State private var targetFolderID: UUID?

    private let columns = [GridItem(.adaptive(minimum: 290, maximum: 420), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Rule Presets")
                            .font(.title2.weight(.semibold))
                        Text("Install common folder automation templates in one click.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    if !store.workspace.folders.isEmpty {
                        Picker("Target Folder", selection: Binding(
                            get: { targetFolderID ?? store.workspace.folders.first?.id },
                            set: { targetFolderID = $0 }
                        )) {
                            ForEach(store.workspace.folders) { f in
                                Text(f.name).tag(Optional(f.id))
                            }
                        }
                        .frame(width: 240)
                    }
                }

                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(DemoWorkspaceGenerator.curatedPresets) { preset in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Image(systemName: preset.symbolName)
                                    .font(.system(size: 18))
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 32, height: 32)
                                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.title)
                                        .font(.system(size: 13.5, weight: .semibold))
                                    Text(preset.category.uppercased())
                                        .font(.system(size: 9.5, weight: .bold))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }

                            Text(preset.subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: 4)

                            HStack {
                                Spacer()
                                Button("Install Rule") {
                                    if let fid = targetFolderID ?? store.workspace.folders.first?.id {
                                        store.installPreset(preset, into: fid)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(store.workspace.folders.isEmpty)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 146, alignment: .topLeading)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1)
                        )
                    }
                }
            }
            .padding(22)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct ActivityLogView: View {
    @Bindable var store: RuleBoxStore
    @State private var searchText = ""

    private var filtered: [ActivityEntry] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return store.activity }
        let q = searchText.lowercased()
        return store.activity.filter {
            $0.sourceFileName.lowercased().contains(q)
                || $0.ruleName.lowercased().contains(q)
                || $0.summary.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Activity & Undo Journal")
                        .font(.title2.weight(.semibold))
                    Text("Every file move, rename, archive, and tag change is recorded for 1-click Undo.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TextField("Filter activity…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 210)
                    .controlSize(.small)

                Button("Clear Log") {
                    store.clearActivity()
                }
                .controlSize(.small)
                .disabled(store.activity.isEmpty)
            }
            .padding(18)

            Divider()

            if filtered.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("No Recorded Activity Yet")
                        .font(.headline)
                    Text("Click Run Rules on any folder to process matching files and see reversible entries here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered) { entry in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(colorForStatus(entry.status))
                            .frame(width: 8, height: 8)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(entry.sourceFileName)
                                    .font(.system(size: 12.5, weight: .semibold))
                                Text("·")
                                    .foregroundStyle(.secondary)
                                Text(entry.ruleName)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                            }
                            Text(entry.summary)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)

                        if entry.canUndo {
                            Button("Undo") {
                                store.undoActivity(id: entry.id)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        } else if entry.status == .undone {
                            Text("Undone")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(.quaternary.opacity(0.6), in: Capsule())
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func colorForStatus(_ status: ActivityStatus) -> Color {
        switch status {
        case .success: return .green
        case .skipped: return .secondary
        case .error: return .red
        case .undone: return .orange
        }
    }
}
