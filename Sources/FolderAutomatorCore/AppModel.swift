import Foundation
import SwiftUI

@MainActor
public final class FolderAutomatorModel: ObservableObject {
    @Published public var configuration: AppConfiguration = .default
    @Published public var activity: [ActivityItem] = []
    @Published public var isMonitoring = false
    @Published public var previewItems: [ActivityItem] = []
    @Published public var undoOperations: [UndoOperation] = []
    @Published public var folderSearchText = ""
    @Published public var activitySearchText = ""

    private let store: ConfigurationStore
    private let engine: FileRuleEngine
    private let loginItemManager: LoginItemManager
    private let bookmarkManager: BookmarkManager
    private var monitors: [UUID: FolderMonitor] = [:]
    private var pendingPaths: [UUID: Set<String>] = [:]
    private var debounceTasks: [UUID: Task<Void, Never>] = [:]
    private var processedFiles: [String: ProcessedFileRecord] = [:]
    private let fileManager = FileManager.default

    public init(
        store: ConfigurationStore = .shared,
        engine: FileRuleEngine = .init(),
        loginItemManager: LoginItemManager = .shared,
        bookmarkManager: BookmarkManager = .shared
    ) {
        self.store = store
        self.engine = engine
        self.loginItemManager = loginItemManager
        self.bookmarkManager = bookmarkManager
    }

    public func load() async {
        do {
            configuration = try await store.loadConfiguration()
            activity = try await store.loadActivity()
            processedFiles = try await store.loadProcessedFiles()
            undoOperations = try await store.loadUndoOperations()
        } catch {
            appendActivity(.init(kind: .error, message: "Failed to load configuration: \(error.localizedDescription)"))
        }
    }

    public func save() async {
        do {
            try await store.saveConfiguration(configuration)
            try await loginItemManager.sync(enabled: configuration.general.launchAtLogin)
        } catch {
            appendActivity(.init(kind: .error, message: "Failed to save configuration: \(error.localizedDescription)"))
        }
    }

    public func saveActivity() async {
        do {
            try await store.saveActivity(activity)
            try await store.saveProcessedFiles(processedFiles)
            try await store.saveUndoOperations(undoOperations)
        } catch {
            appendActivity(.init(kind: .error, message: "Failed to save activity log: \(error.localizedDescription)"))
        }
    }

    public func replaceConfiguration(_ configuration: AppConfiguration) {
        self.configuration = configuration
    }

    public func startMonitoring() {
        stopMonitoring()
        guard configuration.general.runRulesAutomatically else { return }

        for folder in configuration.folders where folder.isEnabled {
            let resolvedPath = bookmarkManager.resolvePath(path: folder.path, bookmarkData: folder.bookmarkData)
            let url = URL(fileURLWithPath: resolvedPath)
            let monitor = FolderMonitor(url: url) { [weak self] paths in
                Task { @MainActor [weak self] in
                    self?.scheduleProcessing(for: folder.id, changedPaths: paths)
                }
            }
            monitors[folder.id] = monitor
            monitor.start()
        }

        isMonitoring = !monitors.isEmpty
        appendActivity(.init(kind: .info, message: "Monitoring \(monitors.count) folder(s)"))

        if configuration.general.processExistingFilesOnLaunch {
            Task { @MainActor in
                await processAllFolders()
            }
        }
    }

    public func stopMonitoring() {
        debounceTasks.values.forEach { $0.cancel() }
        debounceTasks.removeAll()
        pendingPaths.removeAll()
        monitors.values.forEach { $0.stop() }
        monitors.removeAll()
        isMonitoring = false
    }

    public func processAllFolders() async {
        for folder in configuration.folders where folder.isEnabled {
            await process(folder: folder, changedPaths: [folder.path])
        }
    }

    public func addFolder() {
        let downloads = PathPicker.chooseFolder(initialPath: ("~/Downloads" as NSString).expandingTildeInPath)
            ?? ("~/Downloads" as NSString).expandingTildeInPath
        let bookmark = try? bookmarkManager.makeBookmark(for: downloads)
        configuration.folders.append(
            WatchedFolder(
                name: "New Folder",
                path: downloads,
                bookmarkData: bookmark,
                rules: [
                    Rule(
                        name: "Rename PDFs",
                        conditions: [
                            RuleCondition(kind: .fileExtension, operator: .equals, value: "pdf")
                        ],
                        actions: [
                            RuleAction(kind: .rename, value: "{date}-{name}.{ext}")
                        ]
                    )
                ]
            )
        )
    }

    public func removeFolders(at offsets: IndexSet) {
        configuration.folders.remove(atOffsets: offsets)
    }

    public func choosePath(for folderID: UUID) {
        guard let index = configuration.folders.firstIndex(where: { $0.id == folderID }),
              let path = PathPicker.chooseFolder(initialPath: configuration.folders[index].path) else {
            return
        }

        configuration.folders[index].path = path
        configuration.folders[index].bookmarkData = try? bookmarkManager.makeBookmark(for: path)
        if configuration.folders[index].name == "New Folder" {
            configuration.folders[index].name = URL(fileURLWithPath: path).lastPathComponent
        }
    }

    public func chooseActionPath(folderID: UUID, ruleID: UUID, actionID: UUID) {
        guard
            let folderIndex = configuration.folders.firstIndex(where: { $0.id == folderID }),
            let ruleIndex = configuration.folders[folderIndex].rules.firstIndex(where: { $0.id == ruleID }),
            let actionIndex = configuration.folders[folderIndex].rules[ruleIndex].actions.firstIndex(where: { $0.id == actionID }),
            let path = PathPicker.chooseFolder(initialPath: configuration.folders[folderIndex].rules[ruleIndex].actions[actionIndex].value)
        else {
            return
        }

        configuration.folders[folderIndex].rules[ruleIndex].actions[actionIndex].value = path
        configuration.folders[folderIndex].rules[ruleIndex].actions[actionIndex].bookmarkData = try? bookmarkManager.makeBookmark(for: path)
    }

    public func clearActivity() {
        activity.removeAll()
    }

    public func resetProcessedFiles() {
        processedFiles.removeAll()
        appendActivity(.init(kind: .info, message: "Reset processed-file tracking state"))
        Task {
            await saveActivity()
        }
    }

    public func exportConfiguration() async {
        guard let path = PathPicker.chooseExportFile() else { return }

        do {
            try await store.exportConfiguration(configuration, to: URL(fileURLWithPath: path))
            appendActivity(.init(kind: .success, message: "Exported configuration to \(path)"))
            await saveActivity()
        } catch {
            appendActivity(.init(kind: .error, message: "Failed to export configuration: \(error.localizedDescription)"))
        }
    }

    public func importConfiguration() async {
        guard let path = PathPicker.chooseFile() else { return }

        do {
            let imported = try await store.importConfiguration(from: URL(fileURLWithPath: path))
            configuration = imported
            appendActivity(.init(kind: .success, message: "Imported configuration from \(path)"))
            await save()
            await saveActivity()
        } catch {
            appendActivity(.init(kind: .error, message: "Failed to import configuration: \(error.localizedDescription)"))
        }
    }

    public func undoLastOperation() async {
        guard let operation = undoOperations.first else {
            appendActivity(.init(kind: .info, message: "No reversible operation is available"))
            return
        }

        do {
            let message = try engine.undo(operation)
            undoOperations.removeFirst()
            appendActivity(.init(kind: .success, message: message, filePath: operation.destinationPath ?? operation.sourcePath))
            await saveActivity()
        } catch {
            appendActivity(.init(kind: .error, message: "Undo failed: \(error.localizedDescription)", filePath: operation.sourcePath))
        }
    }

    public var filteredFolders: [WatchedFolder] {
        guard !folderSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return configuration.folders
        }

        let query = folderSearchText.lowercased()
        return configuration.folders.filter { folder in
            folder.name.lowercased().contains(query) ||
            folder.path.lowercased().contains(query) ||
            folder.rules.contains(where: { $0.name.lowercased().contains(query) })
        }
    }

    public var filteredActivity: [ActivityItem] {
        guard !activitySearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return activity
        }

        let query = activitySearchText.lowercased()
        return activity.filter { item in
            item.message.lowercased().contains(query) ||
            (item.ruleName?.lowercased().contains(query) ?? false) ||
            (item.filePath?.lowercased().contains(query) ?? false)
        }
    }

    public func preview(folderID: UUID, filePath: String) async {
        guard
            let folder = configuration.folders.first(where: { $0.id == folderID }),
            !filePath.isEmpty
        else {
            previewItems = [.init(kind: .error, message: "Choose a file to preview.")]
            return
        }

        let url = URL(fileURLWithPath: filePath)
        let record = processedFiles[url.standardizedFileURL.path]
        let options = RuleExecutionOptions(
            dryRun: true,
            skipPreviouslyMatchedFiles: configuration.general.skipPreviouslyMatchedFiles,
            previouslyMatchedRuleIDs: Set(record?.matchedRuleIDs ?? []),
            stopAfterFirstMatchPerFile: configuration.general.stopAfterFirstMatchPerFile
        )

        do {
            let result = try engine.evaluate(folder: folder, fileURL: url, options: options)
            previewItems = result.activity.isEmpty ? [.init(kind: .info, message: "No rules would run for \(url.lastPathComponent).", filePath: url.path)] : result.activity
        } catch {
            previewItems = [.init(kind: .error, message: "Preview failed: \(error.localizedDescription)", filePath: url.path)]
        }
    }

    private func scheduleProcessing(for folderID: UUID, changedPaths: [String]) {
        pendingPaths[folderID, default: []].formUnion(changedPaths)
        debounceTasks[folderID]?.cancel()
        debounceTasks[folderID] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, let folder = self.configuration.folders.first(where: { $0.id == folderID }) else { return }
            let paths = Array(self.pendingPaths[folderID] ?? [])
            self.pendingPaths[folderID] = []
            await self.process(folder: folder, changedPaths: paths)
        }
    }

    private func process(folder: WatchedFolder, changedPaths: [String]) async {
        guard folder.isEnabled else { return }

        var fileURLs = Set<URL>()
        for path in changedPaths {
            let url = URL(fileURLWithPath: path)
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    fileURLs.formUnion(scanFiles(in: url, recursive: folder.includeSubfolders))
                } else {
                    fileURLs.insert(url)
                }
            }
        }

        for fileURL in fileURLs.sorted(by: { $0.path < $1.path }) {
            if configuration.general.ignoreHiddenFiles && fileURL.lastPathComponent.hasPrefix(".") {
                continue
            }

            do {
                let record = currentRecord(for: fileURL)
                let options = RuleExecutionOptions(
                    dryRun: configuration.general.dryRunMode,
                    skipPreviouslyMatchedFiles: configuration.general.skipPreviouslyMatchedFiles,
                    previouslyMatchedRuleIDs: Set(record?.matchedRuleIDs ?? []),
                    stopAfterFirstMatchPerFile: configuration.general.stopAfterFirstMatchPerFile
                )
                let result = try engine.evaluate(folder: folder, fileURL: fileURL, options: options)
                result.activity.forEach(appendActivity)
                if !result.undoOperations.isEmpty {
                    undoOperations.insert(contentsOf: result.undoOperations.reversed(), at: 0)
                    if undoOperations.count > configuration.general.maxActivityItems {
                        undoOperations = Array(undoOperations.prefix(configuration.general.maxActivityItems))
                    }
                }
                updateProcessedRecord(for: fileURL, matchedRuleIDs: result.matchedRuleIDs)
            } catch {
                appendActivity(.init(kind: .error, message: "Rule execution failed for \(fileURL.lastPathComponent): \(error.localizedDescription)"))
            }
        }

        await saveActivity()
    }

    private func scanFiles(in root: URL, recursive: Bool) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
        let options: FileManager.DirectoryEnumerationOptions = recursive ? [.skipsPackageDescendants] : [.skipsSubdirectoryDescendants, .skipsPackageDescendants]

        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: keys, options: options) else {
            return []
        }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            if let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true {
                urls.append(url)
            }
        }
        return urls
    }

    private func appendActivity(_ item: ActivityItem) {
        activity.insert(item, at: 0)
        if activity.count > configuration.general.maxActivityItems {
            activity = Array(activity.prefix(configuration.general.maxActivityItems))
        }
    }

    private func currentRecord(for fileURL: URL) -> ProcessedFileRecord? {
        let key = fileURL.standardizedFileURL.path
        guard let record = processedFiles[key] else { return nil }

        let currentModificationDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? nil
        if record.lastModificationDate != currentModificationDate {
            return ProcessedFileRecord(filePath: key, lastModificationDate: currentModificationDate, matchedRuleIDs: [])
        }
        return record
    }

    private func updateProcessedRecord(for fileURL: URL, matchedRuleIDs: [UUID]) {
        let key = fileURL.standardizedFileURL.path
        let modificationDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? nil
        var existing = processedFiles[key] ?? ProcessedFileRecord(filePath: key, lastModificationDate: modificationDate)
        existing.lastProcessedAt = Date()
        existing.lastModificationDate = modificationDate
        existing.matchedRuleIDs = Array(Set(existing.matchedRuleIDs).union(matchedRuleIDs)).sorted { $0.uuidString < $1.uuidString }
        processedFiles[key] = existing
    }
}
