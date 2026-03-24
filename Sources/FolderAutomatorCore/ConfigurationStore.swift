import Foundation

public actor ConfigurationStore {
    public static let shared = ConfigurationStore()

    public enum ConfigurationError: LocalizedError {
        case unsupportedConfigurationVersion(Int)

        public var errorDescription: String? {
            switch self {
            case .unsupportedConfigurationVersion(let version):
                return "Unsupported configuration version: \(version)"
            }
        }
    }

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let configURL: URL
    private let activityURL: URL
    private let activityLogURL: URL
    private let processedURL: URL
    private let undoOperationsURL: URL
    private let logFormatter: ISO8601DateFormatter

    public init(baseURL: URL? = nil, fileManager: FileManager = .default) {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        logFormatter = ISO8601DateFormatter()
        logFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let resolvedBaseURL: URL
        if let baseURL {
            resolvedBaseURL = baseURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            resolvedBaseURL = appSupport.appendingPathComponent("FolderAutomator", isDirectory: true)
        }
        configURL = resolvedBaseURL.appendingPathComponent("configuration.json")
        activityURL = resolvedBaseURL.appendingPathComponent("activity.json")
        activityLogURL = resolvedBaseURL.appendingPathComponent("activity.log")
        processedURL = resolvedBaseURL.appendingPathComponent("processed-files.json")
        undoOperationsURL = resolvedBaseURL.appendingPathComponent("undo-operations.json")
    }

    public func loadConfiguration() throws -> AppConfiguration {
        try ensureStorage()

        guard FileManager.default.fileExists(atPath: configURL.path) else {
            let config = AppConfiguration.default
            try saveConfiguration(config)
            return config
        }

        let data = try Data(contentsOf: configURL)
        if let versioned = try? decoder.decode(VersionedAppConfiguration.self, from: data) {
            guard versioned.version <= VersionedAppConfiguration.currentVersion else {
                throw ConfigurationError.unsupportedConfigurationVersion(versioned.version)
            }
            return try migrate(versioned)
        }

        // Legacy unversioned configuration.json files stored the raw AppConfiguration object.
        return try decoder.decode(AppConfiguration.self, from: data)
    }

    public func saveConfiguration(_ configuration: AppConfiguration) throws {
        try ensureStorage()
        let data = try encoder.encode(VersionedAppConfiguration(configuration: configuration))
        try data.write(to: configURL, options: .atomic)
    }

    public func loadActivity() throws -> [ActivityItem] {
        try ensureStorage()

        guard FileManager.default.fileExists(atPath: activityURL.path) else {
            return []
        }

        let data = try Data(contentsOf: activityURL)
        return try decoder.decode([ActivityItem].self, from: data)
    }

    public func saveActivity(_ items: [ActivityItem]) throws {
        try ensureStorage()
        let data = try encoder.encode(items)
        try data.write(to: activityURL, options: .atomic)
    }

    public func appendActivityLog(_ item: ActivityItem) throws {
        try ensureStorage()
        let line = formatLogLine(for: item)
        let data = Data(line.utf8)

        if FileManager.default.fileExists(atPath: activityLogURL.path) == false {
            try data.write(to: activityLogURL, options: .atomic)
            return
        }

        let handle = try FileHandle(forWritingTo: activityLogURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    public func loadActivityLog() throws -> String {
        try ensureStorage()
        guard FileManager.default.fileExists(atPath: activityLogURL.path) else {
            return ""
        }
        return try String(contentsOf: activityLogURL)
    }

    public func loadProcessedFiles() throws -> [String: ProcessedFileRecord] {
        try ensureStorage()

        guard FileManager.default.fileExists(atPath: processedURL.path) else {
            return [:]
        }

        let data = try Data(contentsOf: processedURL)
        return try decoder.decode([String: ProcessedFileRecord].self, from: data)
    }

    public func saveProcessedFiles(_ processedFiles: [String: ProcessedFileRecord]) throws {
        try ensureStorage()
        let data = try encoder.encode(processedFiles)
        try data.write(to: processedURL, options: .atomic)
    }

    public func loadUndoOperations() throws -> [UndoOperation] {
        try ensureStorage()

        guard FileManager.default.fileExists(atPath: undoOperationsURL.path) else {
            return []
        }

        let data = try Data(contentsOf: undoOperationsURL)
        return try decoder.decode([UndoOperation].self, from: data)
    }

    public func saveUndoOperations(_ operations: [UndoOperation]) throws {
        try ensureStorage()
        let data = try encoder.encode(operations)
        try data.write(to: undoOperationsURL, options: .atomic)
    }

    public func exportConfiguration(_ configuration: AppConfiguration, to destinationURL: URL) throws {
        try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(VersionedAppConfiguration(configuration: configuration))
        try data.write(to: destinationURL, options: .atomic)
    }

    public func importConfiguration(from sourceURL: URL) throws -> AppConfiguration {
        let data = try Data(contentsOf: sourceURL)
        if let versioned = try? decoder.decode(VersionedAppConfiguration.self, from: data) {
            guard versioned.version <= VersionedAppConfiguration.currentVersion else {
                throw ConfigurationError.unsupportedConfigurationVersion(versioned.version)
            }
            return try migrate(versioned)
        }
        return try decoder.decode(AppConfiguration.self, from: data)
    }

    public func currentActivityLogURL() -> URL {
        activityLogURL
    }

    private func ensureStorage() throws {
        let directory = configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func formatLogLine(for item: ActivityItem) -> String {
        var components = [
            logFormatter.string(from: item.timestamp),
            "[\(item.kind.rawValue.uppercased())]",
            item.message
        ]

        if let ruleName = item.ruleName, ruleName.isEmpty == false {
            components.append("rule=\(ruleName)")
        }
        if let filePath = item.filePath, filePath.isEmpty == false {
            components.append("file=\(filePath)")
        }
        if let undoSummary = item.undoSummary, undoSummary.isEmpty == false {
            components.append("undo=\(undoSummary)")
        }

        return components.joined(separator: " | ") + "\n"
    }

    private func migrate(_ versioned: VersionedAppConfiguration) throws -> AppConfiguration {
        switch versioned.version {
        case 1, 2:
            return versioned.configuration
        default:
            throw ConfigurationError.unsupportedConfigurationVersion(versioned.version)
        }
    }
}
