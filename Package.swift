// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FolderAutomator",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "FolderAutomatorCore",
            targets: ["FolderAutomatorCore"]
        ),
        .executable(
            name: "FolderAutomatorApp",
            targets: ["FolderAutomatorApp"]
        ),
        .executable(
            name: "FolderAutomatorSettingsApp",
            targets: ["FolderAutomatorSettingsApp"]
        )
    ],
    targets: [
        .target(
            name: "FolderAutomatorCore"
        ),
        .executableTarget(
            name: "FolderAutomatorApp",
            dependencies: ["FolderAutomatorCore"]
        ),
        .executableTarget(
            name: "FolderAutomatorSettingsApp",
            dependencies: ["FolderAutomatorCore"]
        ),
        .testTarget(
            name: "FolderAutomatorCoreTests",
            dependencies: ["FolderAutomatorCore"]
        )
    ]
)
