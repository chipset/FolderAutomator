import XCTest
@testable import FolderAutomatorCore

final class ConfigurationStoreTests: XCTestCase {
    func testConfigurationRoundTrip() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ConfigurationStore(baseURL: root)
        let config = AppConfiguration(
            folders: [
                WatchedFolder(name: "Inbox", path: "/tmp/inbox", bookmarkData: "bookmark", rules: [])
            ],
            general: GeneralSettings(dryRunMode: true, skipPreviouslyMatchedFiles: true)
        )

        try await store.saveConfiguration(config)
        let loaded = try await store.loadConfiguration()

        XCTAssertEqual(loaded, config)
    }

    func testProcessedFilesRoundTrip() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ConfigurationStore(baseURL: root)
        let processed = [
            "/tmp/file.txt": ProcessedFileRecord(
                filePath: "/tmp/file.txt",
                lastModificationDate: Date(timeIntervalSince1970: 123),
                matchedRuleIDs: [UUID()]
            )
        ]

        try await store.saveProcessedFiles(processed)
        let loaded = try await store.loadProcessedFiles()

        XCTAssertEqual(loaded.keys, processed.keys)
        XCTAssertEqual(loaded["/tmp/file.txt"]?.filePath, processed["/tmp/file.txt"]?.filePath)
        XCTAssertEqual(loaded["/tmp/file.txt"]?.lastModificationDate, processed["/tmp/file.txt"]?.lastModificationDate)
        XCTAssertEqual(loaded["/tmp/file.txt"]?.matchedRuleIDs, processed["/tmp/file.txt"]?.matchedRuleIDs)
    }

    func testUndoOperationsRoundTrip() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ConfigurationStore(baseURL: root)
        let operations = [
            UndoOperation(kind: .move, sourcePath: "/tmp/after.txt", destinationPath: "/tmp/before.txt"),
            UndoOperation(kind: .copy, sourcePath: "/tmp/copied.txt")
        ]

        try await store.saveUndoOperations(operations)
        let loaded = try await store.loadUndoOperations()

        XCTAssertEqual(loaded.map(\.id), operations.map(\.id))
        XCTAssertEqual(loaded.map(\.kind), operations.map(\.kind))
        XCTAssertEqual(loaded.map(\.sourcePath), operations.map(\.sourcePath))
        XCTAssertEqual(loaded.map(\.destinationPath), operations.map(\.destinationPath))
    }

    func testImportExportConfigurationRoundTrip() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let exportURL = root.appendingPathComponent("export.json")
        let store = ConfigurationStore(baseURL: root)
        let config = AppConfiguration(
            folders: [
                WatchedFolder(
                    name: "Photos",
                    path: "/tmp/photos",
                    rules: [
                        Rule(
                            name: "Wide images",
                            conditions: [RuleCondition(kind: .imageWidth, operator: .greaterThan, value: "1600")],
                            actions: [RuleAction(kind: .move, value: "/tmp/wide")]
                        )
                    ]
                )
            ],
            general: GeneralSettings(dryRunMode: true, skipPreviouslyMatchedFiles: true, stopAfterFirstMatchPerFile: true)
        )

        try await store.exportConfiguration(config, to: exportURL)
        let imported = try await store.importConfiguration(from: exportURL)

        XCTAssertEqual(imported, config)
    }
}
