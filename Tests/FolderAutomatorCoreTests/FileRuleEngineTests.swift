import XCTest
@testable import FolderAutomatorCore

final class FileRuleEngineTests: XCTestCase {
    func testDryRunDoesNotMoveFile() async throws {
        let directory = try makeTemporaryDirectory()
        let source = directory.appendingPathComponent("example.zip")
        let destination = directory.appendingPathComponent("Archives", isDirectory: true)
        try "hello".data(using: .utf8)?.write(to: source)

        let folder = WatchedFolder(
            name: "Downloads",
            path: directory.path,
            rules: [
                Rule(
                    name: "Archive ZIP files",
                    conditions: [
                        RuleCondition(kind: .fileExtension, operator: .equals, value: "zip")
                    ],
                    actions: [
                        RuleAction(kind: .move, value: destination.path)
                    ]
                )
            ]
        )

        let engine = FileRuleEngine()
        let result = try engine.evaluate(
            folder: folder,
            fileURL: source,
            options: RuleExecutionOptions(dryRun: true, skipPreviouslyMatchedFiles: false)
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(result.matchedRuleIDs.count, 1)
        XCTAssertTrue(result.activity.contains(where: { $0.message.contains("Would move") }))
    }

    func testSkipPreviouslyMatchedRulePreventsAction() async throws {
        let directory = try makeTemporaryDirectory()
        let source = directory.appendingPathComponent("invoice.pdf")
        let destination = directory.appendingPathComponent("Sorted", isDirectory: true)
        try "hello".data(using: .utf8)?.write(to: source)

        let rule = Rule(
            name: "Move invoices",
            conditions: [
                RuleCondition(kind: .name, operator: .contains, value: "invoice")
            ],
            actions: [
                RuleAction(kind: .move, value: destination.path)
            ]
        )

        let folder = WatchedFolder(name: "Inbox", path: directory.path, rules: [rule])
        let engine = FileRuleEngine()
        let result = try engine.evaluate(
            folder: folder,
            fileURL: source,
            options: RuleExecutionOptions(dryRun: false, skipPreviouslyMatchedFiles: true, previouslyMatchedRuleIDs: [rule.id])
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(result.activity.contains(where: { $0.message.contains("Skipped previously matched rule") }))
    }

    func testContentContainsConditionMatchesTextFile() throws {
        let directory = try makeTemporaryDirectory()
        let source = directory.appendingPathComponent("notes.txt")
        try "hazel style workflow".data(using: .utf8)?.write(to: source)

        let folder = WatchedFolder(
            name: "Inbox",
            path: directory.path,
            rules: [
                Rule(
                    name: "Match contents",
                    conditions: [
                        RuleCondition(kind: .contentContains, operator: .contains, value: "workflow")
                    ],
                    actions: [
                        RuleAction(kind: .notify, value: "Matched text")
                    ]
                )
            ]
        )

        let engine = FileRuleEngine()
        let result = try engine.evaluate(folder: folder, fileURL: source, options: RuleExecutionOptions(dryRun: true, skipPreviouslyMatchedFiles: false))

        XCTAssertEqual(result.matchedRuleIDs.count, 1)
        XCTAssertTrue(result.activity.contains(where: { $0.message.contains("Would show notification") }))
    }

    func testDuplicateFilenameConditionFindsSiblingMatch() throws {
        let directory = try makeTemporaryDirectory()
        let first = directory.appendingPathComponent("report.txt")
        let otherDir = directory.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: otherDir, withIntermediateDirectories: true)
        let second = otherDir.appendingPathComponent("report.txt")
        try "a".data(using: .utf8)?.write(to: first)
        try "b".data(using: .utf8)?.write(to: second)

        let folder = WatchedFolder(
            name: "Inbox",
            path: directory.path,
            rules: [
                Rule(
                    name: "Find duplicates",
                    conditions: [
                        RuleCondition(kind: .duplicateFileName, operator: .isTrue, value: "")
                    ],
                    actions: [
                        RuleAction(kind: .notify, value: "Duplicate found")
                    ]
                )
            ]
        )

        let engine = FileRuleEngine()
        let result = try engine.evaluate(folder: folder, fileURL: first, options: RuleExecutionOptions(dryRun: true, skipPreviouslyMatchedFiles: false))

        XCTAssertEqual(result.matchedRuleIDs.count, 1)
        XCTAssertTrue(result.activity.contains(where: { $0.message.contains("Would show notification") }))
    }

    func testContentRegexConditionMatchesTextFile() throws {
        let directory = try makeTemporaryDirectory()
        let source = directory.appendingPathComponent("statement.txt")
        try "invoice #482 ready".data(using: .utf8)?.write(to: source)

        let folder = WatchedFolder(
            name: "Inbox",
            path: directory.path,
            rules: [
                Rule(
                    name: "Regex contents",
                    conditions: [
                        RuleCondition(kind: .contentMatchesRegex, operator: .matchesRegex, value: #"invoice\s+#\d+"#)
                    ],
                    actions: [
                        RuleAction(kind: .notify, value: "Regex matched")
                    ]
                )
            ]
        )

        let result = try FileRuleEngine().evaluate(
            folder: folder,
            fileURL: source,
            options: RuleExecutionOptions(dryRun: true, skipPreviouslyMatchedFiles: false)
        )

        XCTAssertEqual(result.matchedRuleIDs.count, 1)
    }

    func testDuplicateContentHashConditionFindsMatchingContent() throws {
        let directory = try makeTemporaryDirectory()
        let first = directory.appendingPathComponent("a.txt")
        let second = directory.appendingPathComponent("b.txt")
        try "same payload".data(using: .utf8)?.write(to: first)
        try "same payload".data(using: .utf8)?.write(to: second)

        let folder = WatchedFolder(
            name: "Inbox",
            path: directory.path,
            rules: [
                Rule(
                    name: "Hash duplicates",
                    conditions: [
                        RuleCondition(kind: .duplicateContentHash, operator: .isTrue, value: "")
                    ],
                    actions: [
                        RuleAction(kind: .notify, value: "Duplicate content")
                    ]
                )
            ]
        )

        let result = try FileRuleEngine().evaluate(
            folder: folder,
            fileURL: first,
            options: RuleExecutionOptions(dryRun: true, skipPreviouslyMatchedFiles: false)
        )

        XCTAssertEqual(result.matchedRuleIDs.count, 1)
    }

    func testArchiveEntryConditionMatchesZipContents() throws {
        let directory = try makeTemporaryDirectory()
        let archiveSourceDir = directory.appendingPathComponent("archive-src", isDirectory: true)
        try FileManager.default.createDirectory(at: archiveSourceDir, withIntermediateDirectories: true)
        let nestedDir = archiveSourceDir.appendingPathComponent("Invoices", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
        try "pdf".data(using: .utf8)?.write(to: nestedDir.appendingPathComponent("March.pdf"))
        let archive = directory.appendingPathComponent("bundle.zip")
        try zipDirectory(at: archiveSourceDir, to: archive)

        let folder = WatchedFolder(
            name: "Inbox",
            path: directory.path,
            rules: [
                Rule(
                    name: "Archive inspection",
                    conditions: [
                        RuleCondition(kind: .archiveEntryName, operator: .contains, value: "Invoices/")
                    ],
                    actions: [
                        RuleAction(kind: .notify, value: "Archive matched")
                    ]
                )
            ]
        )

        let result = try FileRuleEngine().evaluate(
            folder: folder,
            fileURL: archive,
            options: RuleExecutionOptions(dryRun: true, skipPreviouslyMatchedFiles: false)
        )

        XCTAssertEqual(result.matchedRuleIDs.count, 1)
    }

    func testFilenameDateConditionMatchesRecentDate() throws {
        let directory = try makeTemporaryDirectory()
        let source = directory.appendingPathComponent("report-2026-03-20.txt")
        try "dated".data(using: .utf8)?.write(to: source)

        let folder = WatchedFolder(
            name: "Inbox",
            path: directory.path,
            rules: [
                Rule(
                    name: "Recent filename date",
                    conditions: [
                        RuleCondition(kind: .filenameDate, operator: .newerThanDays, value: "10")
                    ],
                    actions: [
                        RuleAction(kind: .notify, value: "Recent file")
                    ]
                )
            ]
        )

        let result = try FileRuleEngine().evaluate(
            folder: folder,
            fileURL: source,
            options: RuleExecutionOptions(dryRun: true, skipPreviouslyMatchedFiles: false)
        )

        XCTAssertEqual(result.matchedRuleIDs.count, 1)
    }

    func testNestedConditionGroupMatches() throws {
        let directory = try makeTemporaryDirectory()
        let source = directory.appendingPathComponent("report-2026.txt")
        try "quarterly summary".data(using: .utf8)?.write(to: source)

        let rule = Rule(
            name: "Nested groups",
            matchMode: .all,
            conditions: [RuleCondition(kind: .fileExtension, operator: .equals, value: "txt")],
            conditionGroups: [
                RuleConditionGroup(
                    matchMode: .any,
                    conditions: [
                        RuleCondition(kind: .name, operator: .contains, value: "report"),
                        RuleCondition(kind: .contentContains, operator: .contains, value: "invoice")
                    ]
                )
            ],
            actions: [RuleAction(kind: .notify, value: "Grouped")]
        )

        let result = try FileRuleEngine().evaluate(
            folder: WatchedFolder(name: "Inbox", path: directory.path, rules: [rule]),
            fileURL: source,
            options: RuleExecutionOptions(dryRun: true, skipPreviouslyMatchedFiles: false)
        )

        XCTAssertEqual(result.matchedRuleIDs, [rule.id])
    }

    func testStopAfterFirstMatchPreventsLaterRules() throws {
        let directory = try makeTemporaryDirectory()
        let source = directory.appendingPathComponent("sample.txt")
        try "sample".data(using: .utf8)?.write(to: source)

        let firstRule = Rule(
            name: "First",
            conditions: [RuleCondition(kind: .fileExtension, operator: .equals, value: "txt")],
            actions: [RuleAction(kind: .notify, value: "First")],
            stopProcessingAfterMatch: true
        )
        let secondRule = Rule(
            name: "Second",
            conditions: [RuleCondition(kind: .fileExtension, operator: .equals, value: "txt")],
            actions: [RuleAction(kind: .notify, value: "Second")]
        )

        let result = try FileRuleEngine().evaluate(
            folder: WatchedFolder(name: "Inbox", path: directory.path, rules: [firstRule, secondRule]),
            fileURL: source,
            options: RuleExecutionOptions(dryRun: true, skipPreviouslyMatchedFiles: false)
        )

        XCTAssertEqual(result.matchedRuleIDs, [firstRule.id])
    }

    func testMoveCreatesUndoOperationAndUndoRestoresFile() throws {
        let directory = try makeTemporaryDirectory()
        let source = directory.appendingPathComponent("invoice.txt")
        let destination = directory.appendingPathComponent("Sorted", isDirectory: true)
        try "hello".data(using: .utf8)?.write(to: source)

        let rule = Rule(
            name: "Move file",
            conditions: [RuleCondition(kind: .name, operator: .contains, value: "invoice")],
            actions: [RuleAction(kind: .move, value: destination.path)]
        )

        let engine = FileRuleEngine()
        let result = try engine.evaluate(
            folder: WatchedFolder(name: "Inbox", path: directory.path, rules: [rule]),
            fileURL: source,
            options: RuleExecutionOptions(dryRun: false, skipPreviouslyMatchedFiles: false)
        )

        XCTAssertEqual(result.undoOperations.count, 1)
        let movedFile = destination.appendingPathComponent("invoice.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: movedFile.path))

        let message = try engine.undo(result.undoOperations[0])
        XCTAssertTrue(message.contains("Restored"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testDeleteActionRemovesFile() throws {
        let directory = try makeTemporaryDirectory()
        let source = directory.appendingPathComponent("old.tmp")
        try "temporary".data(using: .utf8)?.write(to: source)

        let rule = Rule(
            name: "Delete temp files",
            conditions: [RuleCondition(kind: .fileExtension, operator: .equals, value: "tmp")],
            actions: [RuleAction(kind: .delete, value: "")]
        )

        let result = try FileRuleEngine().evaluate(
            folder: WatchedFolder(name: "Inbox", path: directory.path, rules: [rule]),
            fileURL: source,
            options: RuleExecutionOptions(dryRun: false, skipPreviouslyMatchedFiles: false)
        )

        XCTAssertEqual(result.matchedRuleIDs, [rule.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(result.activity.contains(where: { $0.message.contains("Permanently deleted") }))
    }

    func testMoveReplaceOverwritesExistingDestinationFile() throws {
        let directory = try makeTemporaryDirectory()
        let source = directory.appendingPathComponent("invoice.txt")
        let destination = directory.appendingPathComponent("Sorted", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let existing = destination.appendingPathComponent("invoice.txt")
        try "new".data(using: .utf8)?.write(to: source)
        try "old".data(using: .utf8)?.write(to: existing)

        let rule = Rule(
            name: "Move and overwrite",
            conditions: [RuleCondition(kind: .name, operator: .contains, value: "invoice")],
            actions: [RuleAction(kind: .move, value: destination.path, conflictPolicy: .replace)]
        )

        let result = try FileRuleEngine().evaluate(
            folder: WatchedFolder(name: "Inbox", path: directory.path, rules: [rule]),
            fileURL: source,
            options: RuleExecutionOptions(dryRun: false, skipPreviouslyMatchedFiles: false)
        )

        XCTAssertEqual(result.matchedRuleIDs, [rule.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try String(contentsOf: existing), "new")
        XCTAssertTrue(result.activity.contains(where: { $0.message.contains("Moved") }))
    }

    func testMoveSkipLeavesSourceUntouchedWhenDestinationExists() throws {
        let directory = try makeTemporaryDirectory()
        let source = directory.appendingPathComponent("invoice.txt")
        let destination = directory.appendingPathComponent("Sorted", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let existing = destination.appendingPathComponent("invoice.txt")
        try "new".data(using: .utf8)?.write(to: source)
        try "old".data(using: .utf8)?.write(to: existing)

        let rule = Rule(
            name: "Move and skip",
            conditions: [RuleCondition(kind: .name, operator: .contains, value: "invoice")],
            actions: [RuleAction(kind: .move, value: destination.path, conflictPolicy: .skip)]
        )

        let result = try FileRuleEngine().evaluate(
            folder: WatchedFolder(name: "Inbox", path: directory.path, rules: [rule]),
            fileURL: source,
            options: RuleExecutionOptions(dryRun: false, skipPreviouslyMatchedFiles: false)
        )

        XCTAssertEqual(result.matchedRuleIDs, [rule.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try String(contentsOf: source), "new")
        XCTAssertEqual(try String(contentsOf: existing), "old")
        XCTAssertTrue(result.activity.contains(where: { $0.message.contains("Skipped move") }))
    }

    func testInlineShellScriptActionRunsScriptBody() throws {
        let directory = try makeTemporaryDirectory()
        let source = directory.appendingPathComponent("example.txt")
        let output = directory.appendingPathComponent("inline-output.txt")
        try "sample".data(using: .utf8)?.write(to: source)

        let rule = Rule(
            name: "Inline script",
            conditions: [RuleCondition(kind: .fileExtension, operator: .equals, value: "txt")],
            actions: [
                RuleAction(
                    kind: .shellScript,
                    value: "pwd > '\(output.path)'"
                )
            ]
        )

        let result = try FileRuleEngine().evaluate(
            folder: WatchedFolder(name: "Inbox", path: directory.path, rules: [rule]),
            fileURL: source,
            options: RuleExecutionOptions(dryRun: false, skipPreviouslyMatchedFiles: false)
        )

        XCTAssertEqual(result.matchedRuleIDs, [rule.id])
        XCTAssertEqual(
            normalizePath(try String(contentsOf: output).trimmingCharacters(in: .whitespacesAndNewlines)),
            normalizePath(directory.path)
        )
        XCTAssertTrue(result.activity.contains(where: { $0.message.contains("Ran shell script") }))
    }

    func testFileShellScriptActionRunsSelectedScriptFileInSelectedWorkingDirectory() throws {
        let directory = try makeTemporaryDirectory()
        let source = directory.appendingPathComponent("example.txt")
        let script = directory.appendingPathComponent("runner.zsh")
        let workingDirectory = directory.appendingPathComponent("Scripts", isDirectory: true)
        let output = directory.appendingPathComponent("file-output.txt")
        try "sample".data(using: .utf8)?.write(to: source)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        let scriptBody = #"pwd > "__OUTPUT__""#
            .replacingOccurrences(of: "__OUTPUT__", with: output.path)
        try XCTUnwrap(scriptBody.data(using: .utf8)).write(to: script)

        let rule = Rule(
            name: "File script",
            conditions: [RuleCondition(kind: .fileExtension, operator: .equals, value: "txt")],
            actions: [
                RuleAction(
                    kind: .shellScript,
                    value: script.path,
                    bookmarkData: nil,
                    shellScriptSource: .file,
                    useFileLocationAsWorkingDirectory: false,
                    shellScriptWorkingDirectoryPath: workingDirectory.path
                )
            ]
        )

        let result = try FileRuleEngine().evaluate(
            folder: WatchedFolder(name: "Inbox", path: directory.path, rules: [rule]),
            fileURL: source,
            options: RuleExecutionOptions(dryRun: false, skipPreviouslyMatchedFiles: false)
        )

        XCTAssertEqual(result.matchedRuleIDs, [rule.id])
        XCTAssertEqual(
            normalizePath(try String(contentsOf: output).trimmingCharacters(in: .whitespacesAndNewlines)),
            normalizePath(workingDirectory.path)
        )
        XCTAssertTrue(result.activity.contains(where: { $0.message.contains("Ran shell script") }))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func normalizePath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    private func zipDirectory(at sourceDirectory: URL, to archiveURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-r", archiveURL.path, "."]
        process.currentDirectoryURL = sourceDirectory
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
