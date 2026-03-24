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
        let rawFile = try String(contentsOf: root.appendingPathComponent("configuration.json"))

        XCTAssertEqual(loaded, config)
        XCTAssertTrue(rawFile.contains(#""version" : 2"#))
        XCTAssertTrue(rawFile.contains(#""configuration""#))
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
        let exportContents = try String(contentsOf: exportURL)

        XCTAssertEqual(imported, config)
        XCTAssertTrue(exportContents.contains(#""version" : 2"#))
    }

    func testActivityLogAppendsEntries() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ConfigurationStore(baseURL: root)
        let first = ActivityItem(kind: .info, message: "Monitoring started", filePath: "/tmp/inbox", ruleName: "Watch Inbox")
        let second = ActivityItem(kind: .error, message: "Rule failed", filePath: "/tmp/inbox/file.txt")

        try await store.appendActivityLog(first)
        try await store.appendActivityLog(second)

        let logContents = try await store.loadActivityLog()
        let logURL = await store.currentActivityLogURL()

        XCTAssertTrue(FileManager.default.fileExists(atPath: logURL.path))
        XCTAssertTrue(logContents.contains("Monitoring started"))
        XCTAssertTrue(logContents.contains("Rule failed"))
        XCTAssertTrue(logContents.contains("[INFO]"))
        XCTAssertTrue(logContents.contains("[ERROR]"))
    }

    func testLegacyConfigurationWithoutNewShellScriptFieldsStillLoads() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = ConfigurationStore(baseURL: root)
        let legacyConfiguration = """
        {
          "folders": [
            {
              "id": "E65488C4-BE7D-48EE-9890-BE7B206290A6",
              "includeSubfolders": true,
              "isEnabled": true,
              "name": "Downloads",
              "path": "/Users/thomas/Downloads",
              "rules": [
                {
                  "actions": [
                    {
                      "conflictPolicy": "unique",
                      "id": "F020F3A3-8ECC-42EB-A8FB-86A54D568EE5",
                      "kind": "shellScript",
                      "shellScriptSource": "file",
                      "value": "/Users/thomas/Documents/source/pdf-extract/run.sh"
                    }
                  ],
                  "conditionGroups": [],
                  "conditions": [
                    {
                      "id": "5FF4585D-6380-4B1A-9BDC-118034D5ABE1",
                      "kind": "name",
                      "operator": "startsWith",
                      "value": "TimeClock"
                    }
                  ],
                  "id": "B0181D4B-93B8-4D6F-8CCE-B02676BDBF55",
                  "isEnabled": true,
                  "matchMode": "all",
                  "name": "InputFiles",
                  "runOncePerFile": false,
                  "stopProcessingAfterMatch": false
                }
              ]
            }
          ],
          "general": {
            "dryRunMode": false,
            "ignoreHiddenFiles": true,
            "launchAtLogin": false,
            "maxActivityItems": 200,
            "processExistingFilesOnLaunch": true,
            "runRulesAutomatically": true,
            "skipPreviouslyMatchedFiles": true,
            "stopAfterFirstMatchPerFile": false
          }
        }
        """

        let configURL = root.appendingPathComponent("configuration.json")
        try legacyConfiguration.write(to: configURL, atomically: true, encoding: .utf8)

        let loaded = try await store.loadConfiguration()
        let action = try XCTUnwrap(loaded.folders.first?.rules.first?.actions.first)

        XCTAssertEqual(action.kind, .shellScript)
        XCTAssertEqual(action.shellScriptSource, .file)
        XCTAssertTrue(action.useFileLocationAsWorkingDirectory)
        XCTAssertEqual(action.shellScriptWorkingDirectoryPath, "")
    }

    func testCurrentVersionedConfigurationLoads() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = ConfigurationStore(baseURL: root)
        let versionedConfiguration = """
        {
          "version": 2,
          "configuration": {
            "folders": [],
            "general": {
              "dryRunMode": true,
              "ignoreHiddenFiles": true,
              "launchAtLogin": false,
              "maxActivityItems": 200,
              "processExistingFilesOnLaunch": true,
              "runRulesAutomatically": true,
              "skipPreviouslyMatchedFiles": true,
              "stopAfterFirstMatchPerFile": false
            }
          }
        }
        """

        try versionedConfiguration.write(to: root.appendingPathComponent("configuration.json"), atomically: true, encoding: .utf8)

        let loaded = try await store.loadConfiguration()

        XCTAssertTrue(loaded.general.dryRunMode)
        XCTAssertEqual(loaded.folders.count, 0)
    }
}
