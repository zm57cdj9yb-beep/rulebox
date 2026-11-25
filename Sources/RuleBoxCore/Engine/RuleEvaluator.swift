import Foundation

/// Evaluates rule conditions and simulates dry-run outcomes without mutating the filesystem.
public enum RuleEvaluator {
    public static func matches(
        rule: AutomationRule,
        file: FileSnapshot,
        now: Date = Date()
    ) -> Bool {
        guard !rule.conditions.isEmpty else { return false }

        var cachedText: String?
        func textContent() -> String {
            if let existing = cachedText { return existing }
            let extracted = FileInspector.extractSearchableText(from: file)
            cachedText = extracted
            return extracted
        }

        func eval(_ cond: RuleCondition) -> Bool {
            switch cond.field {
            case .name:
                return matchString(file.fileName, op: cond.op, target: cond.value, caseSensitive: cond.caseSensitive)
            case .fileExtension:
                let ext = file.fileExtension
                if cond.op == .inList {
                    let allowed = cond.value
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
                        .filter { !$0.isEmpty }
                    return allowed.contains(ext.lowercased())
                }
                let cleanedTarget = cond.value.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
                return matchString(ext, op: cond.op, target: cleanedTarget, caseSensitive: cond.caseSensitive)
            case .kind:
                let isEqual = file.kind.rawValue.caseInsensitiveCompare(cond.value) == .orderedSame
                return cond.op == .notEquals ? !isEqual : isEqual
            case .sizeMB:
                guard let threshold = Double(cond.value.replacingOccurrences(of: ",", with: ".")) else { return false }
                return cond.op == .lessThan ? (file.sizeMB < threshold) : (file.sizeMB > threshold)
            case .ageDays:
                guard let threshold = Double(cond.value.replacingOccurrences(of: ",", with: ".")) else { return false }
                let age = file.ageDays(relativeTo: now)
                return cond.op == .lessThan ? (age < threshold) : (age > threshold)
            case .contents:
                let txt = textContent()
                guard !txt.isEmpty else { return cond.op == .doesNotContain }
                return matchString(txt, op: cond.op, target: cond.value, caseSensitive: cond.caseSensitive)
            case .finderTag:
                let hasTag = file.tags.contains { $0.caseInsensitiveCompare(cond.value) == .orderedSame }
                return cond.op == .notEquals ? !hasTag : hasTag
            case .isHidden:
                return cond.op == .isFalse ? !file.isHidden : file.isHidden
            }
        }

        switch rule.matchMode {
        case .all:
            return rule.conditions.allSatisfy(eval)
        case .any:
            return rule.conditions.contains(where: eval)
        case .none:
            return !rule.conditions.contains(where: eval)
        }
    }

    private static func matchString(
        _ haystack: String,
        op: ConditionOperator,
        target: String,
        caseSensitive: Bool
    ) -> Bool {
        guard !target.isEmpty else { return false }
        let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]

        switch op {
        case .contains:
            return haystack.range(of: target, options: options) != nil
        case .doesNotContain:
            return haystack.range(of: target, options: options) == nil
        case .startsWith:
            return haystack.range(of: target, options: options.union(.anchored)) != nil
        case .endsWith:
            return haystack.range(of: target, options: options.union([.anchored, .backwards])) != nil
        case .equals:
            return haystack.compare(target, options: options) == .orderedSame
        case .notEquals:
            return haystack.compare(target, options: options) != .orderedSame
        case .matchesRegex:
            let regexOpts: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
            guard let re = try? NSRegularExpression(pattern: target, options: regexOpts) else { return false }
            let range = NSRange(haystack.startIndex..<haystack.endIndex, in: haystack)
            return re.firstMatch(in: haystack, options: [], range: range) != nil
        default:
            return false
        }
    }

    /// Simulates all enabled rules in a watched folder and returns exact dry-run matches.
    public static func dryRun(
        folder: WatchedFolder,
        now: Date = Date()
    ) -> [DryRunMatch] {
        let files = FileInspector.listFiles(
            in: URL(fileURLWithPath: folder.path),
            includeSubfolders: folder.includeSubfolders
        )
        return dryRun(folder: folder, files: files, now: now)
    }

    public static func dryRun(
        folder: WatchedFolder,
        files: [FileSnapshot],
        now: Date = Date()
    ) -> [DryRunMatch] {
        var results: [DryRunMatch] = []
        var counters: [UUID: Int] = [:]

        for file in files {
            for rule in folder.rules where rule.isEnabled {
                if matches(rule: rule, file: file, now: now) {
                    let nextCounter = (counters[rule.id] ?? 0) + 1
                    counters[rule.id] = nextCounter
                    results.append(simulateOutcome(rule: rule, folder: folder, file: file, counter: nextCounter))
                    if rule.stopProcessingMoreRules {
                        break
                    }
                }
            }
        }
        return results
    }

    /// Simulates a single rule (even if currently disabled) against a folder for live Rule Editor preview.
    public static func previewRule(
        rule: AutomationRule,
        in folder: WatchedFolder,
        now: Date = Date()
    ) -> [DryRunMatch] {
        let files = FileInspector.listFiles(
            in: URL(fileURLWithPath: folder.path),
            includeSubfolders: folder.includeSubfolders
        )
        var results: [DryRunMatch] = []
        var counter = 0
        for file in files {
            if matches(rule: rule, file: file, now: now) {
                counter += 1
                results.append(simulateOutcome(rule: rule, folder: folder, file: file, counter: counter))
            }
        }
        return results
    }

    public static func simulateOutcome(
        rule: AutomationRule,
        folder: WatchedFolder,
        file: FileSnapshot,
        counter: Int
    ) -> DryRunMatch {
        var currentURL = file.url
        var badges: [String] = []
        var willTrash = false
        let folderRoot = URL(fileURLWithPath: folder.path).standardizedFileURL

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
                currentURL = currentURL.deletingLastPathComponent().appendingPathComponent(cleanName)
                badges.append("Rename")
            case .sortIntoSubfolder:
                let expanded = TokenExpander.expand(
                    pattern: action.pattern,
                    fileURL: currentURL,
                    kind: file.kind,
                    referenceDate: file.modificationDate,
                    counter: counter
                )
                let sub = TokenExpander.sanitizeRelativeSubfolder(expanded)
                if !sub.isEmpty {
                    currentURL = folderRoot.appendingPathComponent(sub).appendingPathComponent(currentURL.lastPathComponent)
                    badges.append("Subfolder")
                }
            case .move:
                if !action.targetPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let expandedDest = TokenExpander.expand(
                        pattern: action.targetPath,
                        fileURL: currentURL,
                        kind: file.kind,
                        referenceDate: file.modificationDate,
                        counter: counter
                    )
                    currentURL = URL(fileURLWithPath: expandedDest).appendingPathComponent(currentURL.lastPathComponent)
                    badges.append("Move")
                }
            case .copy:
                if !action.targetPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    badges.append("Copy -> \(URL(fileURLWithPath: action.targetPath).lastPathComponent)")
                }
            case .addTag:
                badges.append("+\(action.tagName)")
            case .removeTags:
                badges.append("Clear Tags")
            case .archiveZip:
                currentURL = currentURL.deletingLastPathComponent()
                    .appendingPathComponent(currentURL.deletingPathExtension().lastPathComponent + ".zip")
                badges.append("ZIP")
            case .moveToTrash:
                willTrash = true
                badges.append("Trash")
            case .runShellScript:
                badges.append("Script")
            }
        }

        let displayDest: String
        if willTrash {
            displayDest = "Trash"
        } else if currentURL.standardizedFileURL == file.url.standardizedFileURL {
            displayDest = file.fileName
        } else {
            let rootPrefix = folderRoot.path.hasSuffix("/") ? folderRoot.path : folderRoot.path + "/"
            if currentURL.path.hasPrefix(rootPrefix) {
                displayDest = String(currentURL.path.dropFirst(rootPrefix.count))
            } else {
                let parent = currentURL.deletingLastPathComponent().lastPathComponent
                displayDest = "\(parent)/\(currentURL.lastPathComponent)"
            }
        }

        return DryRunMatch(
            ruleID: rule.id,
            ruleName: rule.name,
            sourceURL: file.url,
            fileSizeBytes: file.sizeBytes,
            fileKind: file.kind,
            predictedDestinationPath: willTrash ? nil : currentURL.path,
            predictedDisplayDestination: displayDest,
            actionBadges: badges,
            willTrash: willTrash
        )
    }
}
