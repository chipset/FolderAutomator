import AppKit

let bundleURL = Bundle.main.bundleURL
let settingsAppURL = bundleURL
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

let siblingRunnerURL = settingsAppURL.deletingLastPathComponent().appendingPathComponent("FolderAutomatorApp.app")
let fallbackRunnerURL = URL(fileURLWithPath: "/Applications/FolderAutomatorApp.app")

let workspace = NSWorkspace.shared
let targetURL = FileManager.default.fileExists(atPath: siblingRunnerURL.path) ? siblingRunnerURL : fallbackRunnerURL

if !workspace.runningApplications.contains(where: { $0.bundleURL == targetURL }) {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    workspace.openApplication(at: targetURL, configuration: configuration) { _, _ in
        Task { @MainActor in
            NSApplication.shared.terminate(nil)
        }
    }
} else {
    Task { @MainActor in
        NSApplication.shared.terminate(nil)
    }
}

NSApplication.shared.run()
