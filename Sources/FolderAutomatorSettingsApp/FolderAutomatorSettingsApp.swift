#if canImport(FolderAutomatorCore)
import FolderAutomatorCore
#endif
import SwiftUI

@main
struct FolderAutomatorSettingsAppMain: App {
    @StateObject private var model = FolderAutomatorModel()

    var body: some Scene {
        WindowGroup("FolderAutomator Settings") {
            SettingsRootView(model: model)
                .frame(minWidth: 900, minHeight: 620)
                .toolbar {
                    ToolbarItemGroup {
                        Button("Save") {
                            Task {
                                await model.save()
                            }
                        }
                        Button("Import") {
                            Task {
                                await model.importConfiguration()
                            }
                        }
                        Button("Export") {
                            Task {
                                await model.exportConfiguration()
                            }
                        }
                        Button("Start Monitoring") {
                            model.startMonitoring()
                        }
                    }
                }
        }
    }
}
