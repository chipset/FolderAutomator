import Foundation

public enum RuleMatchMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case all
    case any

    public var id: String { rawValue }
}

public enum ConditionOperator: String, Codable, CaseIterable, Sendable, Identifiable {
    case contains
    case equals
    case startsWith
    case endsWith
    case notContains
    case matchesRegex
    case greaterThan
    case lessThan
    case olderThanDays
    case newerThanDays
    case isTrue

    public var id: String { rawValue }
}

public enum RuleConditionKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case name
    case fileExtension
    case fileSizeMB
    case createdDate
    case modifiedDate
    case tag
    case sourceFolder
    case isDirectory
    case isImage
    case isAudio
    case isVideo
    case uniformType
    case contentContains
    case contentMatchesRegex
    case duplicateFileName
    case duplicateContentHash
    case archiveEntryName
    case filenameDate
    case imageWidth
    case imageHeight

    public var id: String { rawValue }
}

public struct RuleCondition: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var kind: RuleConditionKind
    public var `operator`: ConditionOperator
    public var value: String

    public init(
        id: UUID = UUID(),
        kind: RuleConditionKind,
        operator: ConditionOperator,
        value: String
    ) {
        self.id = id
        self.kind = kind
        self.operator = `operator`
        self.value = value
    }
}

public struct RuleConditionGroup: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var matchMode: RuleMatchMode
    public var conditions: [RuleCondition]
    public var groups: [RuleConditionGroup]

    public init(
        id: UUID = UUID(),
        matchMode: RuleMatchMode = .all,
        conditions: [RuleCondition] = [],
        groups: [RuleConditionGroup] = []
    ) {
        self.id = id
        self.matchMode = matchMode
        self.conditions = conditions
        self.groups = groups
    }
}

public enum ConflictPolicy: String, Codable, CaseIterable, Sendable, Identifiable {
    case unique
    case replace
    case skip

    public var id: String { rawValue }
}

public enum RuleActionKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case move
    case copy
    case rename
    case addTag
    case trash
    case delete
    case shellScript
    case sortIntoSubfolder
    case revealInFinder
    case appendDateToName
    case notify
    case openWithDefaultApp

    public var id: String { rawValue }
}

public enum ShellScriptSource: String, Codable, CaseIterable, Sendable, Identifiable {
    case inline
    case file

    public var id: String { rawValue }
}

public struct RuleAction: Codable, Identifiable, Hashable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case value
        case bookmarkData
        case conflictPolicy
        case shellScriptSource
        case useFileLocationAsWorkingDirectory
        case shellScriptWorkingDirectoryPath
        case shellScriptWorkingDirectoryBookmarkData
    }

    public var id: UUID
    public var kind: RuleActionKind
    public var value: String
    public var bookmarkData: String?
    public var conflictPolicy: ConflictPolicy
    public var shellScriptSource: ShellScriptSource
    public var useFileLocationAsWorkingDirectory: Bool
    public var shellScriptWorkingDirectoryPath: String
    public var shellScriptWorkingDirectoryBookmarkData: String?

    public init(
        id: UUID = UUID(),
        kind: RuleActionKind,
        value: String,
        bookmarkData: String? = nil,
        conflictPolicy: ConflictPolicy = .unique,
        shellScriptSource: ShellScriptSource = .inline,
        useFileLocationAsWorkingDirectory: Bool = true,
        shellScriptWorkingDirectoryPath: String = "",
        shellScriptWorkingDirectoryBookmarkData: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.value = value
        self.bookmarkData = bookmarkData
        self.conflictPolicy = conflictPolicy
        self.shellScriptSource = shellScriptSource
        self.useFileLocationAsWorkingDirectory = useFileLocationAsWorkingDirectory
        self.shellScriptWorkingDirectoryPath = shellScriptWorkingDirectoryPath
        self.shellScriptWorkingDirectoryBookmarkData = shellScriptWorkingDirectoryBookmarkData
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(RuleActionKind.self, forKey: .kind)
        value = try container.decode(String.self, forKey: .value)
        bookmarkData = try container.decodeIfPresent(String.self, forKey: .bookmarkData)
        conflictPolicy = try container.decodeIfPresent(ConflictPolicy.self, forKey: .conflictPolicy) ?? .unique
        shellScriptSource = try container.decodeIfPresent(ShellScriptSource.self, forKey: .shellScriptSource) ?? .inline
        useFileLocationAsWorkingDirectory = try container.decodeIfPresent(Bool.self, forKey: .useFileLocationAsWorkingDirectory) ?? true
        shellScriptWorkingDirectoryPath = try container.decodeIfPresent(String.self, forKey: .shellScriptWorkingDirectoryPath) ?? ""
        shellScriptWorkingDirectoryBookmarkData = try container.decodeIfPresent(String.self, forKey: .shellScriptWorkingDirectoryBookmarkData)
    }
}

public struct Rule: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    public var matchMode: RuleMatchMode
    public var conditions: [RuleCondition]
    public var conditionGroups: [RuleConditionGroup]
    public var actions: [RuleAction]
    public var stopProcessingAfterMatch: Bool
    public var runOncePerFile: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        matchMode: RuleMatchMode = .all,
        conditions: [RuleCondition],
        conditionGroups: [RuleConditionGroup] = [],
        actions: [RuleAction],
        stopProcessingAfterMatch: Bool = false,
        runOncePerFile: Bool = false
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.matchMode = matchMode
        self.conditions = conditions
        self.conditionGroups = conditionGroups
        self.actions = actions
        self.stopProcessingAfterMatch = stopProcessingAfterMatch
        self.runOncePerFile = runOncePerFile
    }
}

public struct WatchedFolder: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var path: String
    public var bookmarkData: String?
    public var isEnabled: Bool
    public var includeSubfolders: Bool
    public var rules: [Rule]

    public init(
        id: UUID = UUID(),
        name: String,
        path: String,
        bookmarkData: String? = nil,
        isEnabled: Bool = true,
        includeSubfolders: Bool = true,
        rules: [Rule]
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.bookmarkData = bookmarkData
        self.isEnabled = isEnabled
        self.includeSubfolders = includeSubfolders
        self.rules = rules
    }
}

public struct GeneralSettings: Codable, Hashable, Sendable {
    public var runRulesAutomatically: Bool
    public var processExistingFilesOnLaunch: Bool
    public var ignoreHiddenFiles: Bool
    public var maxActivityItems: Int
    public var launchAtLogin: Bool
    public var dryRunMode: Bool
    public var skipPreviouslyMatchedFiles: Bool
    public var stopAfterFirstMatchPerFile: Bool

    public init(
        runRulesAutomatically: Bool = true,
        processExistingFilesOnLaunch: Bool = true,
        ignoreHiddenFiles: Bool = true,
        maxActivityItems: Int = 200,
        launchAtLogin: Bool = false,
        dryRunMode: Bool = false,
        skipPreviouslyMatchedFiles: Bool = true,
        stopAfterFirstMatchPerFile: Bool = false
    ) {
        self.runRulesAutomatically = runRulesAutomatically
        self.processExistingFilesOnLaunch = processExistingFilesOnLaunch
        self.ignoreHiddenFiles = ignoreHiddenFiles
        self.maxActivityItems = maxActivityItems
        self.launchAtLogin = launchAtLogin
        self.dryRunMode = dryRunMode
        self.skipPreviouslyMatchedFiles = skipPreviouslyMatchedFiles
        self.stopAfterFirstMatchPerFile = stopAfterFirstMatchPerFile
    }
}

public struct AppConfiguration: Codable, Hashable, Sendable {
    public var folders: [WatchedFolder]
    public var general: GeneralSettings

    public init(
        folders: [WatchedFolder] = [],
        general: GeneralSettings = .init()
    ) {
        self.folders = folders
        self.general = general
    }

    public static let `default`: AppConfiguration = {
        let downloads = ("~/Downloads" as NSString).expandingTildeInPath
        return AppConfiguration(
            folders: [
                WatchedFolder(
                    name: "Downloads",
                    path: downloads,
                    rules: [
                        Rule(
                            name: "Archive ZIP files",
                            conditions: [
                                RuleCondition(kind: .fileExtension, operator: .equals, value: "zip")
                            ],
                            actions: [
                                RuleAction(kind: .move, value: ("~/Downloads/Archives" as NSString).expandingTildeInPath)
                            ]
                        )
                    ]
                )
            ]
        )
    }()
}

public struct VersionedAppConfiguration: Codable, Hashable, Sendable {
    public static let currentVersion = 2

    public var version: Int
    public var configuration: AppConfiguration

    public init(version: Int = VersionedAppConfiguration.currentVersion, configuration: AppConfiguration) {
        self.version = version
        self.configuration = configuration
    }
}

public struct ActivityItem: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case info
        case success
        case error
    }

    public var id: UUID
    public var timestamp: Date
    public var kind: Kind
    public var message: String
    public var filePath: String?
    public var ruleName: String?
    public var undoSummary: String?
    public var undoOperationID: UUID?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        kind: Kind,
        message: String,
        filePath: String? = nil,
        ruleName: String? = nil,
        undoSummary: String? = nil,
        undoOperationID: UUID? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.message = message
        self.filePath = filePath
        self.ruleName = ruleName
        self.undoSummary = undoSummary
        self.undoOperationID = undoOperationID
    }
}

public struct ProcessedFileRecord: Codable, Hashable, Sendable {
    public var filePath: String
    public var lastProcessedAt: Date
    public var lastModificationDate: Date?
    public var matchedRuleIDs: [UUID]

    public init(
        filePath: String,
        lastProcessedAt: Date = Date(),
        lastModificationDate: Date? = nil,
        matchedRuleIDs: [UUID] = []
    ) {
        self.filePath = filePath
        self.lastProcessedAt = lastProcessedAt
        self.lastModificationDate = lastModificationDate
        self.matchedRuleIDs = matchedRuleIDs
    }
}

public enum UndoOperationKind: String, Codable, Hashable, Sendable {
    case move
    case copy
    case rename
    case trash
    case addTag
}

public struct UndoOperation: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var kind: UndoOperationKind
    public var sourcePath: String
    public var destinationPath: String?
    public var metadata: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: UndoOperationKind,
        sourcePath: String,
        destinationPath: String? = nil,
        metadata: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.metadata = metadata
        self.createdAt = createdAt
    }
}
