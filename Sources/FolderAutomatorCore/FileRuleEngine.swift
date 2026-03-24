import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct FileSnapshot: Sendable {
    public let url: URL
    public let name: String
    public let fileExtension: String
    public let sizeInMB: Double
    public let creationDate: Date?
    public let modificationDate: Date?
    public let tags: [String]
    public let isDirectory: Bool
    public let parentFolderName: String
    public let uniformTypeIdentifiers: [String]
    public let parsedFilenameDate: Date?
    public let imagePixelWidth: Double?
    public let imagePixelHeight: Double?
    public let contentHashSHA256: String?
}

public struct RuleExecutionResult: Sendable {
    public let activity: [ActivityItem]
    public let matchedRuleIDs: [UUID]
    public let undoOperations: [UndoOperation]

    public init(
        activity: [ActivityItem],
        matchedRuleIDs: [UUID] = [],
        undoOperations: [UndoOperation] = []
    ) {
        self.activity = activity
        self.matchedRuleIDs = matchedRuleIDs
        self.undoOperations = undoOperations
    }
}

public struct RuleExecutionOptions: Sendable {
    public var dryRun: Bool
    public var skipPreviouslyMatchedFiles: Bool
    public var previouslyMatchedRuleIDs: Set<UUID>
    public var stopAfterFirstMatchPerFile: Bool

    public init(
        dryRun: Bool = false,
        skipPreviouslyMatchedFiles: Bool = true,
        previouslyMatchedRuleIDs: Set<UUID> = [],
        stopAfterFirstMatchPerFile: Bool = false
    ) {
        self.dryRun = dryRun
        self.skipPreviouslyMatchedFiles = skipPreviouslyMatchedFiles
        self.previouslyMatchedRuleIDs = previouslyMatchedRuleIDs
        self.stopAfterFirstMatchPerFile = stopAfterFirstMatchPerFile
    }
}

public enum RuleEngineError: Error, LocalizedError {
    case invalidDestination(String)
    case invalidScript(String)

    public var errorDescription: String? {
        switch self {
        case .invalidDestination(let value):
            return "Invalid destination path: \(value)"
        case .invalidScript(let value):
            return "Shell script failed: \(value)"
        }
    }
}

public final class FileRuleEngine: @unchecked Sendable {
    private let fileManager: FileManager
    private let bookmarkManager: BookmarkManager

    public init(fileManager: FileManager = .default, bookmarkManager: BookmarkManager = .shared) {
        self.fileManager = fileManager
        self.bookmarkManager = bookmarkManager
    }

    public func evaluate(
        folder: WatchedFolder,
        fileURL: URL,
        options: RuleExecutionOptions = .init()
    ) throws -> RuleExecutionResult {
        guard let initialSnapshot = try snapshot(for: fileURL) else {
            return RuleExecutionResult(activity: [])
        }

        var activity: [ActivityItem] = []
        var matchedRuleIDs: [UUID] = []
        var undoOperations: [UndoOperation] = []
        var currentURL = initialSnapshot.url
        var currentSnapshot = initialSnapshot

        for rule in folder.rules where rule.isEnabled && matches(rule: rule, snapshot: currentSnapshot, folder: folder) {
            let shouldSkipForPreviouslyProcessed = options.skipPreviouslyMatchedFiles &&
                (options.previouslyMatchedRuleIDs.contains(rule.id) || (rule.runOncePerFile && !options.previouslyMatchedRuleIDs.isEmpty))

            if shouldSkipForPreviouslyProcessed {
                activity.append(.init(
                    kind: .info,
                    message: "Skipped previously matched rule '\(rule.name)' for \(currentSnapshot.url.lastPathComponent)",
                    filePath: currentSnapshot.url.path,
                    ruleName: rule.name
                ))
                continue
            }

            matchedRuleIDs.append(rule.id)
            activity.append(.init(
                kind: .info,
                message: "Matched rule '\(rule.name)' for \(currentSnapshot.url.lastPathComponent)",
                filePath: currentSnapshot.url.path,
                ruleName: rule.name
            ))

            for action in rule.actions {
                let outcome = try execute(
                    action: action,
                    fileURL: currentURL,
                    ruleName: rule.name,
                    dryRun: options.dryRun
                )
                currentURL = outcome.url
                if !options.dryRun, let updatedSnapshot = try snapshot(for: currentURL) {
                    currentSnapshot = updatedSnapshot
                }
                if let undoOperation = outcome.undoOperation {
                    undoOperations.append(undoOperation)
                }
                activity.append(.init(
                    kind: .success,
                    message: outcome.message,
                    filePath: currentURL.path,
                    ruleName: rule.name,
                    undoSummary: outcome.undoSummary,
                    undoOperationID: outcome.undoOperation?.id
                ))
            }

            if rule.stopProcessingAfterMatch || options.stopAfterFirstMatchPerFile {
                activity.append(.init(
                    kind: .info,
                    message: "Stopped further processing after rule '\(rule.name)'",
                    filePath: currentURL.path,
                    ruleName: rule.name
                ))
                break
            }
        }

        return RuleExecutionResult(activity: activity, matchedRuleIDs: matchedRuleIDs, undoOperations: undoOperations)
    }

    public func snapshot(for fileURL: URL) throws -> FileSnapshot? {
        let values = try fileURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .isDirectoryKey,
            .nameKey,
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey,
            .tagNamesKey
        ])

        guard values.isRegularFile == true || values.isDirectory == true else {
            return nil
        }

        return FileSnapshot(
            url: fileURL,
            name: values.name ?? fileURL.lastPathComponent,
            fileExtension: fileURL.pathExtension.lowercased(),
            sizeInMB: Double(values.fileSize ?? 0) / 1_048_576,
            creationDate: values.creationDate,
            modificationDate: values.contentModificationDate,
            tags: values.tagNames ?? [],
            isDirectory: values.isDirectory == true,
            parentFolderName: fileURL.deletingLastPathComponent().lastPathComponent,
            uniformTypeIdentifiers: inferredTypeIdentifiers(for: fileURL),
            parsedFilenameDate: parseDate(fromFilename: fileURL.deletingPathExtension().lastPathComponent),
            imagePixelWidth: imageDimensions(for: fileURL)?.width,
            imagePixelHeight: imageDimensions(for: fileURL)?.height,
            contentHashSHA256: sha256(for: fileURL)
        )
    }

    public func undo(_ operation: UndoOperation) throws -> String {
        let sourceURL = URL(fileURLWithPath: operation.sourcePath)
        let destinationURL = operation.destinationPath.map(URL.init(fileURLWithPath:))

        switch operation.kind {
        case .move, .rename:
            guard let destinationURL else {
                throw RuleEngineError.invalidDestination(operation.sourcePath)
            }
            if fileManager.fileExists(atPath: sourceURL.path) {
                try fileManager.moveItem(at: sourceURL, to: destinationURL)
            }
            return "Restored \(destinationURL.lastPathComponent)"
        case .copy:
            if fileManager.fileExists(atPath: sourceURL.path) {
                try fileManager.removeItem(at: sourceURL)
            }
            return "Removed copied file \(sourceURL.lastPathComponent)"
        case .trash:
            guard let destinationURL else {
                throw RuleEngineError.invalidDestination(operation.sourcePath)
            }
            if fileManager.fileExists(atPath: sourceURL.path) {
                try fileManager.moveItem(at: sourceURL, to: destinationURL)
            }
            return "Restored \(destinationURL.lastPathComponent) from Trash"
        case .addTag:
            guard let tag = operation.metadata else {
                throw RuleEngineError.invalidScript("Missing Finder tag metadata")
            }
            try removeFinderTag(tag, from: sourceURL)
            return "Removed Finder tag '\(tag)' from \(sourceURL.lastPathComponent)"
        }
    }

    private func matches(rule: Rule, snapshot: FileSnapshot, folder: WatchedFolder) -> Bool {
        let directResults = rule.conditions.map { matches(condition: $0, snapshot: snapshot, folder: folder) }
        let groupResults = rule.conditionGroups.map { matches(group: $0, snapshot: snapshot, folder: folder) }
        let results = directResults + groupResults

        switch rule.matchMode {
        case .all:
            return !results.isEmpty && results.allSatisfy { $0 }
        case .any:
            return results.contains(true)
        }
    }

    private func matches(group: RuleConditionGroup, snapshot: FileSnapshot, folder: WatchedFolder) -> Bool {
        let directResults = group.conditions.map { matches(condition: $0, snapshot: snapshot, folder: folder) }
        let nestedResults = group.groups.map { matches(group: $0, snapshot: snapshot, folder: folder) }
        let results = directResults + nestedResults

        switch group.matchMode {
        case .all:
            return !results.isEmpty && results.allSatisfy { $0 }
        case .any:
            return results.contains(true)
        }
    }

    private func matches(condition: RuleCondition, snapshot: FileSnapshot, folder: WatchedFolder) -> Bool {
        switch condition.kind {
        case .name:
            return compareText(lhs: snapshot.name, condition: condition)
        case .fileExtension:
            return compareText(lhs: snapshot.fileExtension, condition: condition)
        case .tag:
            return snapshot.tags.contains { compareText(lhs: $0, condition: condition) }
        case .sourceFolder:
            return compareText(lhs: snapshot.parentFolderName, condition: condition)
        case .isDirectory:
            return compareBoolean(lhs: snapshot.isDirectory, condition: condition)
        case .isImage:
            return compareBoolean(lhs: isKind(snapshot.fileExtension, in: ["jpg", "jpeg", "png", "gif", "heic", "webp", "tiff"]), condition: condition)
        case .isAudio:
            return compareBoolean(lhs: isKind(snapshot.fileExtension, in: ["mp3", "wav", "m4a", "aac", "flac"]), condition: condition)
        case .isVideo:
            return compareBoolean(lhs: isKind(snapshot.fileExtension, in: ["mov", "mp4", "mkv", "avi", "m4v"]), condition: condition)
        case .uniformType:
            return snapshot.uniformTypeIdentifiers.contains { compareText(lhs: $0, condition: condition) }
        case .contentContains:
            return compareFileContents(snapshot.url, condition: condition, useRegex: false)
        case .contentMatchesRegex:
            return compareFileContents(snapshot.url, condition: condition, useRegex: true)
        case .duplicateFileName:
            return compareBoolean(lhs: hasDuplicateFilename(for: snapshot.url, folder: folder), condition: condition)
        case .duplicateContentHash:
            return compareBoolean(lhs: hasDuplicateContentHash(for: snapshot, folder: folder), condition: condition)
        case .archiveEntryName:
            return archiveEntryNames(for: snapshot.url).contains { compareText(lhs: $0, condition: condition) }
        case .filenameDate:
            return compareDate(snapshot.parsedFilenameDate, condition: condition)
        case .imageWidth:
            return compareNumber(lhs: snapshot.imagePixelWidth, rhsString: condition.value, condition: condition)
        case .imageHeight:
            return compareNumber(lhs: snapshot.imagePixelHeight, rhsString: condition.value, condition: condition)
        case .fileSizeMB:
            return compareNumber(lhs: snapshot.sizeInMB, rhsString: condition.value, condition: condition)
        case .createdDate:
            return compareDate(snapshot.creationDate, condition: condition)
        case .modifiedDate:
            return compareDate(snapshot.modificationDate, condition: condition)
        }
    }

    private func compareText(lhs: String, condition: RuleCondition) -> Bool {
        switch condition.operator {
        case .contains:
            return lhs.localizedCaseInsensitiveContains(condition.value)
        case .equals:
            return lhs.compare(condition.value, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        case .startsWith:
            return lhs.lowercased().hasPrefix(condition.value.lowercased())
        case .endsWith:
            return lhs.lowercased().hasSuffix(condition.value.lowercased())
        case .notContains:
            return !lhs.localizedCaseInsensitiveContains(condition.value)
        case .matchesRegex:
            return (try? NSRegularExpression(pattern: condition.value, options: [.caseInsensitive]))
                .map { regex in
                    let range = NSRange(location: 0, length: lhs.utf16.count)
                    return regex.firstMatch(in: lhs, options: [], range: range) != nil
                } ?? false
        default:
            return false
        }
    }

    private func compareBoolean(lhs: Bool, condition: RuleCondition) -> Bool {
        switch condition.operator {
        case .isTrue:
            return lhs
        default:
            return false
        }
    }

    private func compareNumber(lhs: Double?, rhsString: String, condition: RuleCondition) -> Bool {
        guard let lhs, let rhs = Double(rhsString) else { return false }
        switch condition.operator {
        case .greaterThan:
            return lhs > rhs
        case .lessThan:
            return lhs < rhs
        case .equals:
            return abs(lhs - rhs) < 0.0001
        default:
            return false
        }
    }

    private func compareDate(_ date: Date?, condition: RuleCondition) -> Bool {
        guard let date, let days = Double(condition.value) else { return false }
        let age = Date().timeIntervalSince(date) / 86_400

        switch condition.operator {
        case .olderThanDays:
            return age > days
        case .newerThanDays:
            return age < days
        default:
            return false
        }
    }

    private func execute(
        action: RuleAction,
        fileURL: URL,
        ruleName: String,
        dryRun: Bool
    ) throws -> (url: URL, message: String, undoSummary: String?, undoOperation: UndoOperation?) {
        switch action.kind {
        case .move:
            let destinationDirectory = expandedURL(from: action.value, bookmarkData: action.bookmarkData)
            try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
            let targetURL = resolvedDestination(for: fileURL, in: destinationDirectory, policy: action.conflictPolicy)
            let undo = UndoOperation(kind: .move, sourcePath: targetURL.path, destinationPath: fileURL.path)
            if dryRun {
                return (targetURL, "Would move \(fileURL.lastPathComponent) to \(destinationDirectory.path)", "Move \(targetURL.lastPathComponent) back to \(fileURL.deletingLastPathComponent().path)", undo)
            }
            if shouldSkipOperation(from: fileURL, to: targetURL, policy: action.conflictPolicy) {
                return (fileURL, "Skipped move for \(fileURL.lastPathComponent) because destination already exists", nil, nil)
            }
            if action.conflictPolicy == .replace, fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            }
            try fileManager.moveItem(at: fileURL, to: targetURL)
            return (targetURL, "Moved \(fileURL.lastPathComponent) to \(destinationDirectory.path)", "Move \(targetURL.lastPathComponent) back to \(fileURL.deletingLastPathComponent().path)", undo)
        case .copy:
            let destinationDirectory = expandedURL(from: action.value, bookmarkData: action.bookmarkData)
            try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
            let targetURL = resolvedDestination(for: fileURL, in: destinationDirectory, policy: action.conflictPolicy)
            let undo = UndoOperation(kind: .copy, sourcePath: targetURL.path)
            if dryRun {
                return (fileURL, "Would copy \(fileURL.lastPathComponent) to \(destinationDirectory.path)", "Delete copied file at \(targetURL.path)", undo)
            }
            if shouldSkipOperation(from: fileURL, to: targetURL, policy: action.conflictPolicy) {
                return (fileURL, "Skipped copy for \(fileURL.lastPathComponent) because destination already exists", nil, nil)
            }
            if action.conflictPolicy == .replace, fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            }
            try fileManager.copyItem(at: fileURL, to: targetURL)
            return (fileURL, "Copied \(fileURL.lastPathComponent) to \(destinationDirectory.path)", "Delete copied file at \(targetURL.path)", undo)
        case .rename:
            let targetName = applyRenameTemplate(action.value, fileURL: fileURL)
            let targetURL = resolvedDestination(
                url: fileURL.deletingLastPathComponent().appendingPathComponent(targetName),
                policy: action.conflictPolicy
            )
            let undo = UndoOperation(kind: .rename, sourcePath: targetURL.path, destinationPath: fileURL.path)
            if dryRun {
                return (targetURL, "Would rename \(fileURL.lastPathComponent) to \(targetURL.lastPathComponent)", "Rename \(targetURL.lastPathComponent) back to \(fileURL.lastPathComponent)", undo)
            }
            if shouldSkipOperation(from: fileURL, to: targetURL, policy: action.conflictPolicy) {
                return (fileURL, "Skipped rename for \(fileURL.lastPathComponent) because target already exists", nil, nil)
            }
            if action.conflictPolicy == .replace, fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            }
            try fileManager.moveItem(at: fileURL, to: targetURL)
            return (targetURL, "Renamed \(fileURL.lastPathComponent) to \(targetURL.lastPathComponent)", "Rename \(targetURL.lastPathComponent) back to \(fileURL.lastPathComponent)", undo)
        case .addTag:
            let undo = UndoOperation(kind: .addTag, sourcePath: fileURL.path, metadata: action.value)
            if dryRun {
                return (fileURL, "Would add Finder tag '\(action.value)' to \(fileURL.lastPathComponent)", "Remove Finder tag '\(action.value)' from \(fileURL.lastPathComponent)", undo)
            }
            try setFinderTag(action.value, on: fileURL)
            return (fileURL, "Added Finder tag '\(action.value)' to \(fileURL.lastPathComponent)", "Remove Finder tag '\(action.value)' from \(fileURL.lastPathComponent)", undo)
        case .trash:
            if dryRun {
                let undo = UndoOperation(kind: .trash, sourcePath: fileURL.path, destinationPath: fileURL.path)
                return (fileURL, "Would move \(fileURL.lastPathComponent) to Trash", "Restore \(fileURL.lastPathComponent) from Trash", undo)
            }
            var resultingItemURL: NSURL?
            try fileManager.trashItem(at: fileURL, resultingItemURL: &resultingItemURL)
            let trashedURL = resultingItemURL as URL? ?? fileURL
            let undo = UndoOperation(kind: .trash, sourcePath: trashedURL.path, destinationPath: fileURL.path)
            return (trashedURL, "Moved \(fileURL.lastPathComponent) to Trash", "Restore \(fileURL.lastPathComponent) from Trash", undo)
        case .delete:
            if dryRun {
                return (fileURL, "Would permanently delete \(fileURL.lastPathComponent)", "No automatic undo for permanent delete", nil)
            }
            try fileManager.removeItem(at: fileURL)
            return (fileURL, "Permanently deleted \(fileURL.lastPathComponent)", "No automatic undo for permanent delete", nil)
        case .shellScript:
            if dryRun {
                return (fileURL, "Would run shell script for \(fileURL.lastPathComponent)", "No automatic undo for shell script in rule '\(ruleName)'", nil)
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            switch action.shellScriptSource {
            case .inline:
                process.arguments = ["-lc", action.value]
            case .file:
                let scriptPath = bookmarkManager.resolvePath(path: action.value, bookmarkData: action.bookmarkData)
                process.arguments = [scriptPath]
            }
            process.currentDirectoryURL = shellScriptWorkingDirectory(for: action, fileURL: fileURL)
            process.environment = [
                "OPEN_HAZEL_FILE_PATH": fileURL.path,
                "OPEN_HAZEL_FILE_NAME": fileURL.lastPathComponent,
                "OPEN_HAZEL_WORKING_DIRECTORY": process.currentDirectoryURL?.path ?? fileURL.deletingLastPathComponent().path
            ]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw RuleEngineError.invalidScript(action.value)
            }
            return (fileURL, "Ran shell script for \(fileURL.lastPathComponent)", "No automatic undo for shell script in rule '\(ruleName)'", nil)
        case .sortIntoSubfolder:
            let directoryName = action.value.isEmpty ? inferredSubfolderName(for: fileURL) : action.value
            let destinationDirectory = fileURL.deletingLastPathComponent().appendingPathComponent(directoryName, isDirectory: true)
            try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
            let targetURL = resolvedDestination(for: fileURL, in: destinationDirectory, policy: action.conflictPolicy)
            let undo = UndoOperation(kind: .move, sourcePath: targetURL.path, destinationPath: fileURL.path)
            if dryRun {
                return (targetURL, "Would sort \(fileURL.lastPathComponent) into \(directoryName)", "Move \(targetURL.lastPathComponent) back to \(fileURL.deletingLastPathComponent().path)", undo)
            }
            if shouldSkipOperation(from: fileURL, to: targetURL, policy: action.conflictPolicy) {
                return (fileURL, "Skipped sorting \(fileURL.lastPathComponent) because destination already exists", nil, nil)
            }
            if action.conflictPolicy == .replace, fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            }
            try fileManager.moveItem(at: fileURL, to: targetURL)
            return (targetURL, "Sorted \(fileURL.lastPathComponent) into \(directoryName)", "Move \(targetURL.lastPathComponent) back to \(fileURL.deletingLastPathComponent().path)", undo)
        case .revealInFinder:
            if dryRun {
                return (fileURL, "Would reveal \(fileURL.lastPathComponent) in Finder", nil, nil)
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-R", fileURL.path]
            try process.run()
            process.waitUntilExit()
            return (fileURL, "Revealed \(fileURL.lastPathComponent) in Finder", nil, nil)
        case .appendDateToName:
            let name = fileURL.deletingPathExtension().lastPathComponent
            let ext = fileURL.pathExtension
            let date = ISO8601DateFormatter().string(from: Date()).prefix(10)
            let targetName = ext.isEmpty ? "\(name)-\(date)" : "\(name)-\(date).\(ext)"
            let targetURL = resolvedDestination(url: fileURL.deletingLastPathComponent().appendingPathComponent(targetName), policy: action.conflictPolicy)
            let undo = UndoOperation(kind: .rename, sourcePath: targetURL.path, destinationPath: fileURL.path)
            if dryRun {
                return (targetURL, "Would append date to \(fileURL.lastPathComponent)", "Rename \(targetURL.lastPathComponent) back to \(fileURL.lastPathComponent)", undo)
            }
            if shouldSkipOperation(from: fileURL, to: targetURL, policy: action.conflictPolicy) {
                return (fileURL, "Skipped appending date to \(fileURL.lastPathComponent) because target already exists", nil, nil)
            }
            if action.conflictPolicy == .replace, fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            }
            try fileManager.moveItem(at: fileURL, to: targetURL)
            return (targetURL, "Appended date to \(fileURL.lastPathComponent)", "Rename \(targetURL.lastPathComponent) back to \(fileURL.lastPathComponent)", undo)
        case .notify:
            if dryRun {
                return (fileURL, "Would show notification for \(fileURL.lastPathComponent)", nil, nil)
            }
            try showNotification(title: "FolderAutomator", body: action.value.isEmpty ? fileURL.lastPathComponent : action.value)
            return (fileURL, "Showed notification for \(fileURL.lastPathComponent)", nil, nil)
        case .openWithDefaultApp:
            if dryRun {
                return (fileURL, "Would open \(fileURL.lastPathComponent) with the default app", nil, nil)
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [fileURL.path]
            try process.run()
            process.waitUntilExit()
            return (fileURL, "Opened \(fileURL.lastPathComponent) with the default app", nil, nil)
        }
    }

    private func expandedURL(from path: String, bookmarkData: String?) -> URL {
        let resolvedPath = bookmarkManager.resolvePath(path: path, bookmarkData: bookmarkData)
        let expanded = (resolvedPath as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    private func applyRenameTemplate(_ template: String, fileURL: URL) -> String {
        let stem = fileURL.deletingPathExtension().lastPathComponent
        let ext = fileURL.pathExtension
        let formatter = ISO8601DateFormatter()
        let dateToken = formatter.string(from: Date()).prefix(10)
        let filenameDateToken = parseDate(fromFilename: stem).map {
            ISO8601DateFormatter().string(from: $0).prefix(10)
        } ?? ""

        var output = template
            .replacingOccurrences(of: "{name}", with: stem)
            .replacingOccurrences(of: "{ext}", with: ext)
            .replacingOccurrences(of: "{date}", with: String(dateToken))
            .replacingOccurrences(of: "{filenameDate}", with: String(filenameDateToken))

        if !output.contains(".") && !ext.isEmpty {
            output.append(".\(ext)")
        }

        return output
    }

    private func resolvedDestination(for sourceURL: URL, in directory: URL, policy: ConflictPolicy) -> URL {
        resolvedDestination(url: directory.appendingPathComponent(sourceURL.lastPathComponent), policy: policy)
    }

    private func resolvedDestination(url: URL, policy: ConflictPolicy) -> URL {
        switch policy {
        case .unique:
            return uniqueDestination(url: url)
        case .replace:
            return url
        case .skip:
            return url
        }
    }

    private func shouldSkipOperation(from sourceURL: URL, to targetURL: URL, policy: ConflictPolicy) -> Bool {
        guard policy == .skip else { return false }
        guard sourceURL.standardizedFileURL != targetURL.standardizedFileURL else { return true }
        return fileManager.fileExists(atPath: targetURL.path)
    }

    private func shellScriptWorkingDirectory(for action: RuleAction, fileURL: URL) -> URL {
        if action.useFileLocationAsWorkingDirectory {
            return fileURL.deletingLastPathComponent()
        }

        let path = bookmarkManager.resolvePath(
            path: action.shellScriptWorkingDirectoryPath,
            bookmarkData: action.shellScriptWorkingDirectoryBookmarkData
        )
        if path.isEmpty {
            return fileURL.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    private func uniqueDestination(url: URL) -> URL {
        guard !fileManager.fileExists(atPath: url.path) else {
            let stem = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension

            for index in 1...999 {
                let name = ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
                let candidate = url.deletingLastPathComponent().appendingPathComponent(name)
                if !fileManager.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }

            return url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + (ext.isEmpty ? "" : ".\(ext)"))
        }

        return url
    }

    private func setFinderTag(_ tag: String, on fileURL: URL) throws {
        let escapedTag = tag.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedPath = fileURL.path.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Finder"
            set currentTags to tags of (POSIX file "\(escapedPath)" as alias)
            if currentTags does not contain "\(escapedTag)" then
                set end of currentTags to "\(escapedTag)"
                set tags of (POSIX file "\(escapedPath)" as alias) to currentTags
            end if
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw RuleEngineError.invalidScript("Unable to apply Finder tag")
        }
    }

    private func removeFinderTag(_ tag: String, from fileURL: URL) throws {
        let escapedTag = tag.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedPath = fileURL.path.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Finder"
            set currentTags to tags of (POSIX file "\(escapedPath)" as alias)
            if currentTags contains "\(escapedTag)" then
                set filteredTags to {}
                repeat with currentTag in currentTags
                    if (currentTag as text) is not "\(escapedTag)" then
                        set end of filteredTags to currentTag
                    end if
                end repeat
                set tags of (POSIX file "\(escapedPath)" as alias) to filteredTags
            end if
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw RuleEngineError.invalidScript("Unable to remove Finder tag")
        }
    }

    private func inferredSubfolderName(for fileURL: URL) -> String {
        let ext = fileURL.pathExtension.lowercased()
        return ext.isEmpty ? "Unsorted" : ext.uppercased()
    }

    private func isKind(_ fileExtension: String, in allowedExtensions: Set<String>) -> Bool {
        allowedExtensions.contains(fileExtension.lowercased())
    }

    private func compareFileContents(_ fileURL: URL, condition: RuleCondition, useRegex: Bool) -> Bool {
        guard !condition.value.isEmpty,
              let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]),
              data.count <= 1_000_000,
              let text = String(data: data, encoding: .utf8)
        else {
            return false
        }

        if useRegex {
            let regexCondition = RuleCondition(kind: condition.kind, operator: .matchesRegex, value: condition.value)
            return compareText(lhs: text, condition: regexCondition)
        }
        return compareText(lhs: text, condition: condition)
    }

    private func hasDuplicateFilename(for fileURL: URL, folder: WatchedFolder) -> Bool {
        let root = URL(fileURLWithPath: folder.path)
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return false
        }
        for case let candidate as URL in enumerator {
            if candidate.lastPathComponent == fileURL.lastPathComponent && candidate.standardizedFileURL != fileURL.standardizedFileURL {
                return true
            }
        }
        return false
    }

    private func hasDuplicateContentHash(for snapshot: FileSnapshot, folder: WatchedFolder) -> Bool {
        guard let hash = snapshot.contentHashSHA256 else { return false }
        let root = URL(fileURLWithPath: folder.path)
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return false
        }

        for case let candidate as URL in enumerator where candidate.standardizedFileURL != snapshot.url.standardizedFileURL {
            guard (try? candidate.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            if sha256(for: candidate) == hash {
                return true
            }
        }
        return false
    }

    private func archiveEntryNames(for fileURL: URL) -> [String] {
        guard fileURL.pathExtension.lowercased() == "zip" else { return [] }

        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
        process.arguments = ["-1", fileURL.path]
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return [] }
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            return String(decoding: data, as: UTF8.self)
                .split(separator: "\n")
                .map { String($0) }
        } catch {
            return []
        }
    }

    private func parseDate(fromFilename filename: String) -> Date? {
        let patterns = [
            #"(\d{4})-(\d{2})-(\d{2})"#,
            #"(\d{4})_(\d{2})_(\d{2})"#,
            #"(\d{8})"#,
            #"(\d{2})-(\d{2})-(\d{4})"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(location: 0, length: filename.utf16.count)
            guard let match = regex.firstMatch(in: filename, options: [], range: range) else { continue }
            let matched = (filename as NSString).substring(with: match.range(at: 0))
            if let parsed = parseDateString(matched) {
                return parsed
            }
        }
        return nil
    }

    private func parseDateString(_ string: String) -> Date? {
        let formats = ["yyyy-MM-dd", "yyyy_MM_dd", "yyyyMMdd", "MM-dd-yyyy"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: string) {
                return date
            }
        }
        return nil
    }

    private func imageDimensions(for fileURL: URL) -> (width: Double, height: Double)? {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return nil
        }

        let width = properties[kCGImagePropertyPixelWidth] as? Double ?? (properties[kCGImagePropertyPixelWidth] as? Int).map(Double.init)
        let height = properties[kCGImagePropertyPixelHeight] as? Double ?? (properties[kCGImagePropertyPixelHeight] as? Int).map(Double.init)

        guard let width, let height else { return nil }
        return (width, height)
    }

    private func sha256(for fileURL: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        while let data = try? handle.read(upToCount: 65_536), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func inferredTypeIdentifiers(for fileURL: URL) -> [String] {
        guard let type = UTType(filenameExtension: fileURL.pathExtension) else {
            return []
        }
        var identifiers = [type.identifier]
        identifiers.append(contentsOf: type.supertypes.map(\.identifier))
        return identifiers
    }

    private func showNotification(title: String, body: String) throws {
        let safeTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let safeBody = body.replacingOccurrences(of: "\"", with: "\\\"")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "display notification \"\(safeBody)\" with title \"\(safeTitle)\""]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw RuleEngineError.invalidScript("Unable to display notification")
        }
    }
}
