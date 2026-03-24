#if canImport(FolderAutomatorCore)
import FolderAutomatorCore
#endif
import SwiftUI

@main
struct FolderAutomatorAppMain: App {
    @StateObject private var model = FolderAutomatorModel()

    var body: some Scene {
        MenuBarExtra("FolderAutomator", systemImage: model.isMonitoring ? "wand.and.stars.inverse" : "wand.and.stars") {
            VStack(alignment: .leading, spacing: 12) {
                Text(model.isMonitoring ? "Monitoring is active" : "Monitoring is paused")
                    .font(.headline)

                Button(model.isMonitoring ? "Restart Monitoring" : "Start Monitoring") {
                    Task {
                        await model.load()
                        model.startMonitoring()
                    }
                }

                Button("Run Rules Now") {
                    Task {
                        await model.load()
                        await model.processAllFolders()
                    }
                }

                Button("Undo Last Action") {
                    Task {
                        await model.undoLastOperation()
                    }
                }
                .disabled(model.undoOperations.isEmpty)

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding()
            .frame(width: 240)
        }
        .menuBarExtraStyle(.window)

        Window("Activity", id: "activity") {
            ActivityListView(model: model)
                .frame(minWidth: 520, minHeight: 360)
                .task {
                    await model.load()
                    model.startMonitoring()
                }
                .toolbar {
                    ToolbarItemGroup {
                        Button("Clear") {
                            model.clearActivity()
                        }
                        Button("Undo Last") {
                            Task {
                                await model.undoLastOperation()
                            }
                        }
                        .disabled(model.undoOperations.isEmpty)
                        Button(model.isMonitoring ? "Stop" : "Start") {
                            if model.isMonitoring {
                                model.stopMonitoring()
                            } else {
                                model.startMonitoring()
                            }
                        }
                    }
                }
        }
    }

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}
