import Foundation

/// Executes matched rules atomically on disk, records Undo journals, and reverses operations on 1-click Undo.
public enum RuleExecutor {
    public struct ExecutionReport: Sendable {
        public let entries: [ActivityEntry]
        public let matchedCount: Int
        public let errorCount: Int
    }

    public static func run(folder: WatchedFolder, now: Date = Date()) -> ExecutionReport {
        let files = FileInspector.listFiles(
            in: URL(fileURLWithPath: folder.path),
            includeSubfolders: folder.includeSubfolders
        )
        var entries: [ActivityEntry] = []
        var counters: [UUID: Int] = [:]
        var matchedCount = 0
        var errorCount = 0

        for file in files {
            guard FileManager.default.fileExists(atPath: file.url.path) else { continue }
            for rule in folder.rules where rule.isEnabled {
                if RuleEvaluator.matches(rule: rule, file: file, now: now) {
                    matchedCount += 1
                    let nextCounter = (counters[rule.id] ?? 0) + 1
                    counters[rule.id] = nextCounter
                    let entry = execute(rule: rule, folder: folder, file: file, counter: nextCounter)
                    if entry.status == .error { errorCount += 1 }
                    entries.append(entry)
                    if rule.stopProcessingMoreRules {
                        break
                    }
                }
            }
        }

        return ExecutionReport(entries: entries, matchedCount: matchedCount, errorCount: errorCount)
    }

    public static func execute(
        rule: AutomationRule,
        folder: WatchedFolder,
        file: FileSnapshot,
        counter: Int
    ) -> ActivityEntry {
        let fm = FileManager.default
        let folderRoot = URL(fileURLWithPath: folder.path).standardizedFileURL
        var currentURL = file.url
        var undoRecords: [UndoRecord] = []
        var stepDescriptions: [String] = []

        do {
            for action in rule.actions {
                switch action.kind {
                case .rename:
                    let expanded = TokenExpander.expand(
                        pattern: action.pattern,
                        fileURL: currentURL,
                        kind: file.kind,
                        referenceDate: file.modificationDate,
                        counter: counter
                    )
                    let cleanName = TokenExpander.sanitizeFileName(expanded, fallback: currentURL.lastPathComponent)
                    let target = currentURL.deletingLastPathComponent().appendingPathComponent(cleanName)
                    if target.standardizedFileURL != currentURL.standardizedFileURL {
                        if let resolved = try resolveConflict(target: target, policy: action.conflictPolicy, fm: fm) {
                            let before = currentURL
                            try fm.moveItem(at: before, to: resolved)
                            undoRecords.append(UndoRecord(operation: .moveOrRename, originalPath: before.path, resultingPath: resolved.path))
                            currentURL = resolved
                            stepDescriptions.append("Renamed to \(resolved.lastPathComponent)")
                        } else {
                            stepDescriptions.append("Skipped rename (exists)")
                        }
                    }

                case .sortIntoSubfolder:
                    let expanded = TokenExpander.expand(
                        pattern: action.pattern,
                        fileURL: currentURL,
                        kind: file.kind,
                        referenceDate: file.modificationDate,
                        counter: counter
                    )
                    let sub = TokenExpander.sanitizeRelativeSubfolder(expanded)
                    guard !sub.isEmpty else { continue }
                    let destDir = folderRoot.appendingPathComponent(sub, isDirectory: true)
                    try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
                    let target = destDir.appendingPathComponent(currentURL.lastPathComponent)
                    if target.standardizedFileURL != currentURL.standardizedFileURL {
                        if let resolved = try resolveConflict(target: target, policy: action.conflictPolicy, fm: fm) {
                            let before = currentURL
                            try fm.moveItem(at: before, to: resolved)
                            undoRecords.append(UndoRecord(operation: .moveOrRename, originalPath: before.path, resultingPath: resolved.path))
                            currentURL = resolved
                            stepDescriptions.append("Sorted into \(sub)/")
                        }
                    }

                case .move:
                    let rawTarget = action.targetPath.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !rawTarget.isEmpty else { continue }
                    let expandedDest = TokenExpander.expand(
                        pattern: rawTarget,
                        fileURL: currentURL,
                        kind: file.kind,
                        referenceDate: file.modificationDate,
                        counter: counter
                    )
                    let destDir = URL(fileURLWithPath: expandedDest, isDirectory: true)
                    try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
                    let target = destDir.appendingPathComponent(currentURL.lastPathComponent)
                    if target.standardizedFileURL != currentURL.standardizedFileURL {
                        if let resolved = try resolveConflict(target: target, policy: action.conflictPolicy, fm: fm) {
                            let before = currentURL
                            try fm.moveItem(at: before, to: resolved)
                            undoRecords.append(UndoRecord(operation: .moveOrRename, originalPath: before.path, resultingPath: resolved.path))
                            currentURL = resolved
                            stepDescriptions.append("Moved to \(destDir.lastPathComponent)/")
                        } else {
                            stepDescriptions.append("Skipped move (exists)")
                        }
                    }

                case .copy:
                    let rawTarget = action.targetPath.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !rawTarget.isEmpty else { continue }
                    let destDir = URL(fileURLWithPath: rawTarget, isDirectory: true)
                    try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
                    let target = destDir.appendingPathComponent(currentURL.lastPathComponent)
                    if let resolved = try resolveConflict(target: target, policy: action.conflictPolicy, fm: fm) {
                        try fm.copyItem(at: currentURL, to: resolved)
                        undoRecords.append(UndoRecord(operation: .copyCreated, originalPath: currentURL.path, resultingPath: resolved.path))
                        stepDescriptions.append("Copied to \(destDir.lastPathComponent)/")
                    }

                case .addTag:
                    let tag = action.tagName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !tag.isEmpty else { continue }
                    let prev = (try? currentURL.resourceValues(forKeys: [.tagNamesKey]).tagNames) ?? []
                    if !prev.contains(tag) {
                        var updated = prev
                        updated.append(tag)
                        try (currentURL as NSURL).setResourceValue(updated, forKey: .tagNamesKey)
                        undoRecords.append(UndoRecord(operation: .tagsChanged, originalPath: currentURL.path, resultingPath: currentURL.path, previousTags: prev))
                    }
                    stepDescriptions.append("Tagged \(tag)")

                case .removeTags:
                    let prev = (try? currentURL.resourceValues(forKeys: [.tagNamesKey]).tagNames) ?? []
                    if !prev.isEmpty {
                        try (currentURL as NSURL).setResourceValue([String](), forKey: .tagNamesKey)
                        undoRecords.append(UndoRecord(operation: .tagsChanged, originalPath: currentURL.path, resultingPath: currentURL.path, previousTags: prev))
                    }
                    stepDescriptions.append("Cleared tags")

                case .archiveZip:
                    let zipName = currentURL.deletingPathExtension().lastPathComponent + ".zip"
                    let zipTarget = currentURL.deletingLastPathComponent().appendingPathComponent(zipName)
                    if let resolvedZip = try resolveConflict(target: zipTarget, policy: action.conflictPolicy, fm: fm) {
                        try runDittoZip(source: currentURL, destinationZip: resolvedZip)
                        undoRecords.append(UndoRecord(operation: .archiveCreated, originalPath: currentURL.path, resultingPath: resolvedZip.path))
                        stepDescriptions.append("Archived to \(resolvedZip.lastPathComponent)")
                    }

                case .moveToTrash:
                    var trashedURL: NSURL?
                    try fm.trashItem(at: currentURL, resultingItemURL: &trashedURL)
                    if let resulting = trashedURL as URL? {
                        undoRecords.append(UndoRecord(operation: .moveOrRename, originalPath: currentURL.path, resultingPath: resulting.path))
                    }
                    stepDescriptions.append("Moved to Trash")

                case .runShellScript:
                    let script = action.script.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !script.isEmpty else { continue }
                    try runShellScript(script: script, filePath: currentURL.path, timeoutSeconds: 10.0)
                    stepDescriptions.append("Ran shell script")
                }
            }

            let summary = stepDescriptions.isEmpty ? "Matched (no changes)" : stepDescriptions.joined(separator: " -> ")
            return ActivityEntry(
                folderName: folder.name,
                ruleName: rule.name,
                sourceFileName: file.fileName,
                summary: summary,
                status: stepDescriptions.isEmpty ? .skipped : .success,
                undoRecords: undoRecords
            )
        } catch {
            return ActivityEntry(
                folderName: folder.name,
                ruleName: rule.name,
                sourceFileName: file.fileName,
                summary: "Error: \(error.localizedDescription)",
                status: .error,
                undoRecords: undoRecords
            )
        }
    }

    /// Reverses an ActivityEntry's filesystem changes in reverse chronological order.
    public static func undo(entry: ActivityEntry) throws -> ActivityEntry {
        guard entry.canUndo else { return entry }
        let fm = FileManager.default

        for record in entry.undoRecords.reversed() {
            switch record.operation {
            case .moveOrRename:
                let src = URL(fileURLWithPath: record.resultingPath)
                let dst = URL(fileURLWithPath: record.originalPath)
                if fm.fileExists(atPath: src.path) {
                    try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if fm.fileExists(atPath: dst.path) {
                        try fm.removeItem(at: dst)
                    }
                    try fm.moveItem(at: src, to: dst)
                }
            case .copyCreated, .archiveCreated:
                let created = URL(fileURLWithPath: record.resultingPath)
                if fm.fileExists(atPath: created.path) {
                    try fm.removeItem(at: created)
                }
            case .tagsChanged:
                let url = URL(fileURLWithPath: record.resultingPath)
                if fm.fileExists(atPath: url.path) {
                    try (url as NSURL).setResourceValue(record.previousTags ?? [], forKey: .tagNamesKey)
                }
            }
        }

        var updated = entry
        updated.status = .undone
        updated.undoRecords = []
        return updated
    }

    // MARK: - Helpers

    private static func resolveConflict(target: URL, policy: ConflictPolicy, fm: FileManager) throws -> URL? {
        guard fm.fileExists(atPath: target.path) else { return target }
        switch policy {
        case .skip:
            return nil
        case .overwrite:
            try fm.removeItem(at: target)
            return target
        case .rename:
            let dir = target.deletingLastPathComponent()
            let base = target.deletingPathExtension().lastPathComponent
            let ext = target.pathExtension
            var idx = 2
            while idx < 10_000 {
                let candidateName = ext.isEmpty ? "\(base) \(idx)" : "\(base) \(idx).\(ext)"
                let candidate = dir.appendingPathComponent(candidateName)
                if !fm.fileExists(atPath: candidate.path) {
                    return candidate
                }
                idx += 1
            }
            return target
        }
    }

    private static func runDittoZip(source: URL, destinationZip: URL) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        proc.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", source.path, destinationZip.path]
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            throw NSError(domain: "RuleBox.Archive", code: Int(proc.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "ZIP archive failed with exit code \(proc.terminationStatus)."
            ])
        }
    }

    private static func runShellScript(script: String, filePath: String, timeoutSeconds: TimeInterval) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-c", script, "--", filePath]
        var env = ProcessInfo.processInfo.environment
        env["RULEBOX_FILE"] = filePath
        proc.environment = env

        let errPipe = Pipe()
        proc.standardError = errPipe
        proc.standardOutput = Pipe()

        try proc.run()
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while proc.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if proc.isRunning {
            proc.terminate()
            throw NSError(domain: "RuleBox.Script", code: 124, userInfo: [
                NSLocalizedDescriptionKey: "Shell script timed out after \(Int(timeoutSeconds))s."
            ])
        }
        if proc.terminationStatus != 0 {
            let errText = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "RuleBox.Script", code: Int(proc.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "Script exited \(proc.terminationStatus): \(errText.trimmingCharacters(in: .whitespacesAndNewlines))"
            ])
        }
    }
}
