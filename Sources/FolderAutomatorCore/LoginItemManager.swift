import Foundation
import ServiceManagement

public actor LoginItemManager {
    public static let shared = LoginItemManager()

    private let launchAgentLabel = "com.folderautomator.runner"
    private let helperBundleIdentifier = "com.folderautomator.settings.loginhelper"

    public enum Strategy: String, Sendable {
        case serviceManagement
        case launchAgent
    }

    public func sync(enabled: Bool) async throws {
        if enabled {
            if try enableHelperIfAvailable() == false {
                try installLaunchAgent()
            }
        } else {
            try disableHelperIfAvailable()
            try uninstallLaunchAgent()
        }
    }

    public func activeStrategy() -> Strategy? {
        if helperStatus() == .enabled {
            return .serviceManagement
        }
        if FileManager.default.fileExists(atPath: plistURL.path) {
            return .launchAgent
        }
        return nil
    }

    private func enableHelperIfAvailable() throws -> Bool {
        let service = SMAppService.loginItem(identifier: helperBundleIdentifier)
        guard helperBundleExists() else {
            return false
        }
        if service.status != .enabled {
            try service.register()
        }
        return true
    }

    private func disableHelperIfAvailable() throws {
        let service = SMAppService.loginItem(identifier: helperBundleIdentifier)
        guard service.status == .enabled else { return }
        try service.unregister()
    }

    private func helperStatus() -> SMAppService.Status {
        SMAppService.loginItem(identifier: helperBundleIdentifier).status
    }

    private func helperBundleExists() -> Bool {
        FileManager.default.fileExists(atPath: helperBundleURL.path)
    }

    private func installLaunchAgent() throws {
        try FileManager.default.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)
        let plist = launchAgentDictionary()
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL, options: .atomic)
    }

    private func uninstallLaunchAgent() throws {
        guard FileManager.default.fileExists(atPath: plistURL.path) else { return }
        try FileManager.default.removeItem(at: plistURL)
    }

    private func launchAgentDictionary() -> [String: Any] {
        [
            "Label": launchAgentLabel,
            "ProgramArguments": [runnerExecutablePath()],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive"
        ]
    }

    private func runnerExecutablePath() -> String {
        if let executablePath = Bundle.main.executablePath, executablePath.contains("FolderAutomatorApp") {
            return executablePath
        }

        let mainBundle = Bundle.main.bundleURL
        let siblingFromSettings = mainBundle.deletingLastPathComponent().appendingPathComponent("FolderAutomatorApp.app/Contents/MacOS/FolderAutomatorApp")
        if FileManager.default.fileExists(atPath: siblingFromSettings.path) {
            return siblingFromSettings.path
        }

        let siblingFromLoginItems = mainBundle
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("MacOS/FolderAutomatorSettingsApp")
        if FileManager.default.fileExists(atPath: siblingFromLoginItems.path) {
            return siblingFromLoginItems.path
        }

        return "/Applications/FolderAutomatorApp.app/Contents/MacOS/FolderAutomatorApp"
    }

    private var helperBundleURL: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LoginItems/FolderAutomatorLoginHelper.app")
    }

    private var launchAgentsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    }

    private var plistURL: URL {
        launchAgentsDirectory.appendingPathComponent("\(launchAgentLabel).plist")
    }
}
