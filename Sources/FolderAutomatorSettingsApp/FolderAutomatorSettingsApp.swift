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
                        Button {
                            Task {
                                await model.save()
                            }
                        } label: {
                            Label(
                                model.isSavingConfiguration ? "Saving…" : "Save",
                                systemImage: model.hasUnsavedChanges ? "circle.fill" : "checkmark.circle"
                            )
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .foregroundStyle(model.hasUnsavedChanges ? Color.white : Color.primary)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(model.hasUnsavedChanges ? Color.orange : Color.secondary.opacity(0.14))
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(model.isSavingConfiguration || !model.hasUnsavedChanges)
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
