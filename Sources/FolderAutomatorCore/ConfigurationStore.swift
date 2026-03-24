import Foundation

public actor ConfigurationStore {
    public static let shared = ConfigurationStore()

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let configURL: URL
    private let activityURL: URL
    private let processedURL: URL
    private let undoOperationsURL: URL

    public init(baseURL: URL? = nil, fileManager: FileManager = .default) {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let resolvedBaseURL: URL
        if let baseURL {
            resolvedBaseURL = baseURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            resolvedBaseURL = appSupport.appendingPathComponent("FolderAutomator", isDirectory: true)
        }
        configURL = resolvedBaseURL.appendingPathComponent("configuration.json")
        activityURL = resolvedBaseURL.appendingPathComponent("activity.json")
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
        return try decoder.decode(AppConfiguration.self, from: data)
    }

    public func saveConfiguration(_ configuration: AppConfiguration) throws {
        try ensureStorage()
        let data = try encoder.encode(configuration)
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
        let data = try encoder.encode(configuration)
        try data.write(to: destinationURL, options: .atomic)
    }

    public func importConfiguration(from sourceURL: URL) throws -> AppConfiguration {
        let data = try Data(contentsOf: sourceURL)
        return try decoder.decode(AppConfiguration.self, from: data)
    }

    private func ensureStorage() throws {
        let directory = configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
