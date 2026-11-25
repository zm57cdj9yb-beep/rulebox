import Foundation
import Observation

/// Central `@Observable` state controller for RuleBox managing watched folders, rules,
/// live dry-run previews, kernel `FolderWatcher`, JSON persistence, and 1-click Undo journal.
@MainActor
@Observable
public final class RuleBoxStore {
    public enum SidebarDestination: Hashable {
        case folder(UUID)
        case presets
        case activity
    }

    public var workspace: RuleBoxWorkspace
    public var activity: [ActivityEntry] = []
    public var selection: SidebarDestination?
    public var selectedRuleID: UUID?

    public var dryRunByFolder: [UUID: [DryRunMatch]] = [:]
    public var fileCountByFolder: [UUID: Int] = [:]
    public var selectedRulePreview: [DryRunMatch] = []
    public var statusMessage: String = "Ready"
    public var lastRunDate: Date?

    private let supportDir: URL
    private let workspaceFileURL: URL
    private let activityFileURL: URL
    private var watcher: FolderWatcher?
    private var lastAutoRunByFolder: [UUID: Date] = [:]

    public init(supportDir: URL? = nil, startWatcher: Bool = true) {
        let dir = supportDir ?? DemoWorkspaceGenerator.defaultSupportDirectory()
        self.supportDir = dir
        self.workspaceFileURL = dir.appendingPathComponent("workspace.rulebox")
        self.activityFileURL = dir.appendingPathComponent("activity.json")

        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        if let data = try? Data(contentsOf: workspaceFileURL),
           let decoded = try? JSONDecoder().decode(RuleBoxWorkspace.self, from: data),
           !decoded.folders.isEmpty {
            self.workspace = decoded
        } else {
            let demo = DemoWorkspaceGenerator.ensureDemoWorkspace(baseDir: dir)
            self.workspace = demo
            saveWorkspace()
        }

        if let actData = try? Data(contentsOf: activityFileURL),
           let decodedAct = try? JSONDecoder().decode([ActivityEntry].self, from: actData) {
            self.activity = decodedAct
        }

        if let first = workspace.folders.first {
            self.selection = .folder(first.id)
            self.selectedRuleID = first.rules.first?.id
        }

        refreshAllPreviews()

        if startWatcher {
            self.watcher = FolderWatcher(debounceInterval: 0.5) { [weak self] folderID in
                Task { @MainActor [weak self] in
                    self?.handleWatchedFolderEvent(folderID: folderID)
                }
            }
            syncWatcher()
        }
    }

    public var selectedFolder: WatchedFolder? {
        guard case .folder(let id) = selection else { return nil }
        return workspace.folders.first(where: { $0.id == id })
    }

    public var selectedFolderIndex: Int? {
        guard case .folder(let id) = selection else { return nil }
        return workspace.folders.firstIndex(where: { $0.id == id })
    }

    public var selectedRule: AutomationRule? {
        guard let folder = selectedFolder, let rid = selectedRuleID else { return nil }
        return folder.rules.first(where: { $0.id == rid })
    }

    public var totalRuleCount: Int {
        workspace.folders.reduce(0) { $0 + $1.rules.count }
    }

    public var totalPendingMatches: Int {
        dryRunByFolder.values.reduce(0) { $0 + $1.count }
    }

    public func toggleWatcher() {
        workspace.watcherActive.toggle()
        saveWorkspace()
        syncWatcher()
        statusMessage = workspace.watcherActive ? "Live folder watcher active" : "Folder watcher paused"
    }

    public func syncWatcher() {
        watcher?.sync(folders: workspace.folders, active: workspace.watcherActive)
    }

    public func refreshAllPreviews() {
        var newDry: [UUID: [DryRunMatch]] = [:]
        var newCounts: [UUID: Int] = [:]
        for folder in workspace.folders {
            let files = FileInspector.listFiles(
                in: URL(fileURLWithPath: folder.path),
                includeSubfolders: folder.includeSubfolders
            )
            newCounts[folder.id] = files.count
            newDry[folder.id] = RuleEvaluator.dryRun(folder: folder, files: files)
        }
        dryRunByFolder = newDry
        fileCountByFolder = newCounts
        refreshSelectedRulePreview()
    }

    public func refreshSelectedRulePreview() {
        guard let folder = selectedFolder, let rule = selectedRule else {
            selectedRulePreview = []
            return
        }
        selectedRulePreview = RuleEvaluator.previewRule(rule: rule, in: folder)
    }

    public func matchCount(for ruleID: UUID, in folderID: UUID) -> Int {
        (dryRunByFolder[folderID] ?? []).filter { $0.ruleID == ruleID }.count
    }

    // MARK: - Folder & Rule CRUD

    public func addFolder(url: URL) {
        let path = url.standardizedFileURL.path
        if let existing = workspace.folders.first(where: { $0.path == path }) {
            selection = .folder(existing.id)
            return
        }
        let folder = WatchedFolder(
            name: url.lastPathComponent,
            path: path,
            iconName: "folder.fill",
            isEnabled: true,
            includeSubfolders: false,
            rules: []
        )
        workspace.folders.append(folder)
        selection = .folder(folder.id)
        selectedRuleID = nil
        saveWorkspace()
        syncWatcher()
        refreshAllPreviews()
    }

    public func removeFolder(id: UUID) {
        workspace.folders.removeAll { $0.id == id }
        if case .folder(let current) = selection, current == id {
            selection = workspace.folders.first.map { .folder($0.id) } ?? .presets
            selectedRuleID = selectedFolder?.rules.first?.id
        }
        saveWorkspace()
        syncWatcher()
        refreshAllPreviews()
    }

    public func addNewRule(to folderID: UUID) {
        guard let idx = workspace.folders.firstIndex(where: { $0.id == folderID }) else { return }
        let rule = AutomationRule(
            name: "Untitled Rule",
            isEnabled: true,
            matchMode: .all,
            conditions: [RuleCondition(field: .name, op: .contains, value: "")],
            actions: [RuleAction(kind: .addTag, tagName: "Blue")]
        )
        workspace.folders[idx].rules.append(rule)
        selectedRuleID = rule.id
        saveWorkspace()
        refreshAllPreviews()
    }

    public func installPreset(_ preset: RulePreset, into folderID: UUID) {
        guard let idx = workspace.folders.firstIndex(where: { $0.id == folderID }) else { return }
        let rule = preset.makeRule(workspace.folders[idx].path)
        workspace.folders[idx].rules.append(rule)
        selection = .folder(folderID)
        selectedRuleID = rule.id
        saveWorkspace()
        refreshAllPreviews()
        statusMessage = "Installed preset \"\(preset.title)\" into \(workspace.folders[idx].name)"
    }

    public func updateRule(_ updated: AutomationRule, in folderID: UUID) {
        guard let fIdx = workspace.folders.firstIndex(where: { $0.id == folderID }),
              let rIdx = workspace.folders[fIdx].rules.firstIndex(where: { $0.id == updated.id }) else {
            return
        }
        workspace.folders[fIdx].rules[rIdx] = updated
        saveWorkspace()
        refreshAllPreviews()
    }

    public func deleteRule(id: UUID, from folderID: UUID) {
        guard let fIdx = workspace.folders.firstIndex(where: { $0.id == folderID }) else { return }
        workspace.folders[fIdx].rules.removeAll { $0.id == id }
        if selectedRuleID == id {
            selectedRuleID = workspace.folders[fIdx].rules.first?.id
        }
        saveWorkspace()
        refreshAllPreviews()
    }

    public func duplicateRule(id: UUID, in folderID: UUID) {
        guard let fIdx = workspace.folders.firstIndex(where: { $0.id == folderID }),
              let existing = workspace.folders[fIdx].rules.first(where: { $0.id == id }) else {
            return
        }
        var copy = existing
        copy.id = UUID()
        copy.name = "\(existing.name) Copy"
        copy.conditions = existing.conditions.map { c in
            var nc = c; nc.id = UUID(); return nc
        }
        copy.actions = existing.actions.map { a in
            var na = a; na.id = UUID(); return na
        }
        workspace.folders[fIdx].rules.append(copy)
        selectedRuleID = copy.id
        saveWorkspace()
        refreshAllPreviews()
    }

    public func moveRule(id: UUID, in folderID: UUID, offset: Int) {
        guard let fIdx = workspace.folders.firstIndex(where: { $0.id == folderID }),
              let rIdx = workspace.folders[fIdx].rules.firstIndex(where: { $0.id == id }) else {
            return
        }
        let target = max(0, min(workspace.folders[fIdx].rules.count - 1, rIdx + offset))
        guard target != rIdx else { return }
        let item = workspace.folders[fIdx].rules.remove(at: rIdx)
        workspace.folders[fIdx].rules.insert(item, at: target)
        saveWorkspace()
        refreshAllPreviews()
    }

    // MARK: - Execution & 1-Click Undo

    public func runFolderNow(id: UUID) {
        guard let folder = workspace.folders.first(where: { $0.id == id }) else { return }
        let report = RuleExecutor.run(folder: folder)
        if !report.entries.isEmpty {
            activity.insert(contentsOf: report.entries.reversed(), at: 0)
            if activity.count > 500 {
                activity = Array(activity.prefix(500))
            }
            saveActivity()
        }
        lastRunDate = Date()
        refreshAllPreviews()
        statusMessage = report.matchedCount == 0
            ? "No matching files in \(folder.name)"
            : "Processed \(report.matchedCount) file(s) in \(folder.name)" + (report.errorCount > 0 ? " (\(report.errorCount) error(s))" : "")
    }

    public func runAllFoldersNow() {
        var totalMatched = 0
        var totalErrors = 0
        for folder in workspace.folders where folder.isEnabled {
            let report = RuleExecutor.run(folder: folder)
            totalMatched += report.matchedCount
            totalErrors += report.errorCount
            if !report.entries.isEmpty {
                activity.insert(contentsOf: report.entries.reversed(), at: 0)
            }
        }
        if activity.count > 500 {
            activity = Array(activity.prefix(500))
        }
        saveActivity()
        lastRunDate = Date()
        refreshAllPreviews()
        statusMessage = totalMatched == 0
            ? "All folders up to date"
            : "Processed \(totalMatched) file(s) across \(workspace.folders.count) folders" + (totalErrors > 0 ? " (\(totalErrors) error(s))" : "")
    }

    public func undoActivity(id: UUID) {
        guard let idx = activity.firstIndex(where: { $0.id == id }) else { return }
        do {
            let updated = try RuleExecutor.undo(entry: activity[idx])
            activity[idx] = updated
            saveActivity()
            refreshAllPreviews()
            statusMessage = "Undid action on \(updated.sourceFileName)"
        } catch {
            statusMessage = "Undo failed: \(error.localizedDescription)"
        }
    }

    public func clearActivity() {
        activity.removeAll()
        saveActivity()
    }

    public func resetDemoFiles() {
        let root = supportDir.appendingPathComponent("DemoWorkspace", isDirectory: true)
        let downloads = root.appendingPathComponent("Downloads", isDirectory: true)
        let screenshots = root.appendingPathComponent("Screenshots", isDirectory: true)
        DemoWorkspaceGenerator.populateDemoFiles(downloads: downloads, screenshots: screenshots)
        refreshAllPreviews()
        statusMessage = "Demo sample files restored"
    }

    public func toggleAutoRun(for folderID: UUID) {
        guard let idx = workspace.folders.firstIndex(where: { $0.id == folderID }) else { return }
        workspace.folders[idx].autoRunOnChange.toggle()
        saveWorkspace()
        statusMessage = workspace.folders[idx].autoRunOnChange
            ? "Auto-run enabled for \(workspace.folders[idx].name)"
            : "Auto-run paused for \(workspace.folders[idx].name)"
    }

    private func handleWatchedFolderEvent(folderID: UUID) {
        guard workspace.watcherActive else { return }
        guard let folder = workspace.folders.first(where: { $0.id == folderID && $0.isEnabled }) else { return }
        if folder.autoRunOnChange {
            let now = Date()
            if let prev = lastAutoRunByFolder[folderID], now.timeIntervalSince(prev) < 1.2 {
                refreshAllPreviews()
                return
            }
            lastAutoRunByFolder[folderID] = now
            runFolderNow(id: folderID)
        } else {
            refreshAllPreviews()
        }
    }

    // MARK: - Persistence & Import/Export

    public func exportWorkspace(to url: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(workspace)
        try data.write(to: url, options: .atomic)
    }

    public func importWorkspace(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(RuleBoxWorkspace.self, from: data)
        workspace = decoded
        selection = workspace.folders.first.map { .folder($0.id) } ?? .presets
        selectedRuleID = selectedFolder?.rules.first?.id
        saveWorkspace()
        syncWatcher()
        refreshAllPreviews()
    }

    private func saveWorkspace() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(workspace) {
            try? data.write(to: workspaceFileURL, options: .atomic)
        }
    }

    private func saveActivity() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted]
        if let data = try? enc.encode(activity) {
            try? data.write(to: activityFileURL, options: .atomic)
        }
    }
}
