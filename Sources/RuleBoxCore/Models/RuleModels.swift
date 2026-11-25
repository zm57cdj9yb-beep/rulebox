import Foundation

// MARK: - Core Rule Configuration Models

public enum MatchMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case all = "All"
    case any = "Any"
    case none = "None"

    public var id: String { rawValue }
}

public enum FileKindCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case image = "Image"
    case pdf = "PDF"
    case document = "Document"
    case archive = "Archive"
    case video = "Video"
    case audio = "Audio"
    case diskImage = "Disk Image"
    case code = "Code"
    case folder = "Folder"
    case other = "Other"

    public var id: String { rawValue }
}

public enum ConditionField: String, Codable, CaseIterable, Sendable, Identifiable {
    case name = "Name"
    case fileExtension = "Extension"
    case kind = "Kind"
    case sizeMB = "Size (MB)"
    case ageDays = "Age (Days)"
    case contents = "Contents (Text/PDF)"
    case finderTag = "Finder Tag"
    case isHidden = "Is Hidden"

    public var id: String { rawValue }

    public var defaultOperator: ConditionOperator {
        switch self {
        case .name, .contents: return .contains
        case .fileExtension, .kind, .finderTag: return .equals
        case .sizeMB, .ageDays: return .greaterThan
        case .isHidden: return .isTrue
        }
    }

    public var supportedOperators: [ConditionOperator] {
        switch self {
        case .name:
            return [.contains, .doesNotContain, .startsWith, .endsWith, .equals, .matchesRegex]
        case .fileExtension:
            return [.equals, .notEquals, .inList]
        case .kind:
            return [.equals, .notEquals]
        case .sizeMB, .ageDays:
            return [.greaterThan, .lessThan]
        case .contents:
            return [.contains, .doesNotContain, .matchesRegex]
        case .finderTag:
            return [.equals, .notEquals]
        case .isHidden:
            return [.isTrue, .isFalse]
        }
    }
}

public enum ConditionOperator: String, Codable, CaseIterable, Sendable, Identifiable {
    case contains = "contains"
    case doesNotContain = "does not contain"
    case startsWith = "starts with"
    case endsWith = "ends with"
    case equals = "is"
    case notEquals = "is not"
    case inList = "is in"
    case matchesRegex = "matches regex"
    case greaterThan = "is greater than"
    case lessThan = "is less than"
    case isTrue = "is true"
    case isFalse = "is false"

    public var id: String { rawValue }
}

public struct RuleCondition: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var field: ConditionField
    public var op: ConditionOperator
    public var value: String
    public var caseSensitive: Bool

    public init(
        id: UUID = UUID(),
        field: ConditionField = .name,
        op: ConditionOperator? = nil,
        value: String = "",
        caseSensitive: Bool = false
    ) {
        self.id = id
        self.field = field
        self.op = op ?? field.defaultOperator
        self.value = value
        self.caseSensitive = caseSensitive
    }

    public var shortSummary: String {
        switch op {
        case .isTrue, .isFalse:
            return "\(field.rawValue) \(op.rawValue)"
        default:
            let v = value.isEmpty ? "…" : value
            return "\(field.rawValue) \(op.rawValue) \(v)"
        }
    }
}

public enum ConflictPolicy: String, Codable, CaseIterable, Sendable, Identifiable {
    case rename = "Rename with counter"
    case overwrite = "Overwrite existing"
    case skip = "Skip file"

    public var id: String { rawValue }
}

public enum FinderTagColor: String, Codable, CaseIterable, Sendable, Identifiable {
    case red = "Red"
    case orange = "Orange"
    case yellow = "Yellow"
    case green = "Green"
    case blue = "Blue"
    case purple = "Purple"
    case gray = "Gray"

    public var id: String { rawValue }
}

public enum ActionKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case move = "Move to Folder"
    case copy = "Copy to Folder"
    case rename = "Rename"
    case sortIntoSubfolder = "Sort into Subfolder"
    case addTag = "Add Finder Tag"
    case removeTags = "Remove Finder Tags"
    case archiveZip = "Archive (ZIP)"
    case moveToTrash = "Move to Trash"
    case runShellScript = "Run Shell Script"

    public var id: String { rawValue }

    public var symbolName: String {
        switch self {
        case .move: return "folder.badge.plus"
        case .copy: return "doc.on.doc"
        case .rename: return "pencil.line"
        case .sortIntoSubfolder: return "folder.fill.badge.gearshape"
        case .addTag: return "tag.fill"
        case .removeTags: return "tag.slash"
        case .archiveZip: return "archivebox.fill"
        case .moveToTrash: return "trash"
        case .runShellScript: return "terminal"
        }
    }
}

public struct RuleAction: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var kind: ActionKind
    public var targetPath: String
    public var pattern: String
    public var tagName: String
    public var script: String
    public var conflictPolicy: ConflictPolicy

    public init(
        id: UUID = UUID(),
        kind: ActionKind,
        targetPath: String = "",
        pattern: String = "[Year]-[Month]_[Name].[Ext]",
        tagName: String = "Blue",
        script: String = "",
        conflictPolicy: ConflictPolicy = .rename
    ) {
        self.id = id
        self.kind = kind
        self.targetPath = targetPath
        self.pattern = pattern
        self.tagName = tagName
        self.script = script
        self.conflictPolicy = conflictPolicy
    }

    public var shortSummary: String {
        switch kind {
        case .move:
            let leaf = URL(fileURLWithPath: targetPath).lastPathComponent
            return "Move -> \(leaf.isEmpty ? "…" : leaf)"
        case .copy:
            let leaf = URL(fileURLWithPath: targetPath).lastPathComponent
            return "Copy -> \(leaf.isEmpty ? "…" : leaf)"
        case .rename:
            return "Rename -> \(pattern)"
        case .sortIntoSubfolder:
            return "Subfolder -> \(pattern)"
        case .addTag:
            return "Tag: \(tagName)"
        case .removeTags:
            return "Clear Tags"
        case .archiveZip:
            return "Archive ZIP"
        case .moveToTrash:
            return "Move to Trash"
        case .runShellScript:
            return "Run Script"
        }
    }
}

public struct AutomationRule: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    public var matchMode: MatchMode
    public var conditions: [RuleCondition]
    public var actions: [RuleAction]
    public var stopProcessingMoreRules: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        matchMode: MatchMode = .all,
        conditions: [RuleCondition] = [],
        actions: [RuleAction] = [],
        stopProcessingMoreRules: Bool = true
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.matchMode = matchMode
        self.conditions = conditions
        self.actions = actions
        self.stopProcessingMoreRules = stopProcessingMoreRules
    }
}

public struct WatchedFolder: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var path: String
    public var iconName: String
    public var isEnabled: Bool
    public var includeSubfolders: Bool
    public var rules: [AutomationRule]

    public init(
        id: UUID = UUID(),
        name: String,
        path: String,
        iconName: String = "folder.fill",
        isEnabled: Bool = true,
        includeSubfolders: Bool = false,
        rules: [AutomationRule] = []
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.iconName = iconName
        self.isEnabled = isEnabled
        self.includeSubfolders = includeSubfolders
        self.rules = rules
    }
}

public struct RuleBoxWorkspace: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var watcherActive: Bool
    public var folders: [WatchedFolder]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        watcherActive: Bool = true,
        folders: [WatchedFolder] = []
    ) {
        self.schemaVersion = schemaVersion
        self.watcherActive = watcherActive
        self.folders = folders
    }
}

// MARK: - Dry-Run Preview & Activity / Undo Journal

public struct DryRunMatch: Identifiable, Equatable, Sendable {
    public let id: String
    public let ruleID: UUID
    public let ruleName: String
    public let sourceURL: URL
    public let sourceFileName: String
    public let fileSizeBytes: Int64
    public let fileKind: FileKindCategory
    public let predictedDestinationPath: String?
    public let predictedDisplayDestination: String
    public let actionBadges: [String]
    public let willTrash: Bool

    public init(
        ruleID: UUID,
        ruleName: String,
        sourceURL: URL,
        fileSizeBytes: Int64,
        fileKind: FileKindCategory,
        predictedDestinationPath: String?,
        predictedDisplayDestination: String,
        actionBadges: [String],
        willTrash: Bool
    ) {
        self.id = "\(ruleID.uuidString)::\(sourceURL.path)"
        self.ruleID = ruleID
        self.ruleName = ruleName
        self.sourceURL = sourceURL
        self.sourceFileName = sourceURL.lastPathComponent
        self.fileSizeBytes = fileSizeBytes
        self.fileKind = fileKind
        self.predictedDestinationPath = predictedDestinationPath
        self.predictedDisplayDestination = predictedDisplayDestination
        self.actionBadges = actionBadges
        self.willTrash = willTrash
    }
}

public enum ActivityStatus: String, Codable, Sendable {
    case success
    case skipped
    case error
    case undone
}

public struct UndoRecord: Codable, Equatable, Sendable {
    public enum Operation: String, Codable, Sendable {
        case moveOrRename
        case copyCreated
        case archiveCreated
        case tagsChanged
    }

    public var operation: Operation
    public var originalPath: String
    public var resultingPath: String
    public var previousTags: [String]?

    public init(
        operation: Operation,
        originalPath: String,
        resultingPath: String,
        previousTags: [String]? = nil
    ) {
        self.operation = operation
        self.originalPath = originalPath
        self.resultingPath = resultingPath
        self.previousTags = previousTags
    }
}

public struct ActivityEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var folderName: String
    public var ruleName: String
    public var sourceFileName: String
    public var summary: String
    public var status: ActivityStatus
    public var undoRecords: [UndoRecord]

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        folderName: String,
        ruleName: String,
        sourceFileName: String,
        summary: String,
        status: ActivityStatus,
        undoRecords: [UndoRecord] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.folderName = folderName
        self.ruleName = ruleName
        self.sourceFileName = sourceFileName
        self.summary = summary
        self.status = status
        self.undoRecords = undoRecords
    }

    public var canUndo: Bool {
        status == .success && !undoRecords.isEmpty
    }
}
