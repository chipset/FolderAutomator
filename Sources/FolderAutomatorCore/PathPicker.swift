import AppKit
import Foundation

@MainActor
public enum PathPicker {
    public static func chooseFolder(initialPath: String? = nil) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if let initialPath, !initialPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: (initialPath as NSString).expandingTildeInPath)
        }
        return panel.runModal() == .OK ? panel.urls.first?.path : nil
    }

    public static func chooseFile(initialPath: String? = nil) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        if let initialPath, !initialPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: ((initialPath as NSString).deletingLastPathComponent as NSString).expandingTildeInPath)
        }
        return panel.runModal() == .OK ? panel.urls.first?.path : nil
    }

    public static func chooseExportFile(suggestedName: String = "FolderAutomator-Configuration.json") -> String? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}
