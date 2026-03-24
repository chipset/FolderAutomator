import SwiftUI
import UniformTypeIdentifiers

@MainActor
public struct SettingsRootView: View {
    @ObservedObject var model: FolderAutomatorModel
    @State private var selectedFolderID: UUID?
    @State private var selectedPreviewFolderID: UUID?
    @State private var previewFilePath = ""
    @State private var isDropTargeted = false
    @State private var showingPreferences = false

    public init(model: FolderAutomatorModel) {
        self.model = model
    }

    public var body: some View {
        NavigationSplitView {
            List {
                Section("Overview") {
                    DashboardCardView(model: model)
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                }

                Section("Library") {
                    TextField("Search folders or rules", text: $model.folderSearchText)
                    ForEach(model.filteredFolders) { folder in
                        Button {
                            selectedFolderID = folder.id
                            showingPreferences = false
                        } label: {
                            FolderRow(folder: folder)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteFilteredFolders)

                    DropFolderCardView(isTargeted: isDropTargeted)
                        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted, perform: handleFolderDrop)

                    Button("Add Folder", action: model.addFolder)
                }

                Section("General") {
                    Button("Preferences") {
                        showingPreferences = true
                        selectedFolderID = nil
                    }
                    Button("Import Configuration") {
                        Task { await model.importConfiguration() }
                    }
                    Button("Export Configuration") {
                        Task { await model.exportConfiguration() }
                    }
                    Button("Reset Processed File State") {
                        model.resetProcessedFiles()
                    }
                    .foregroundStyle(.orange)
                }

                Section("Preview") {
                    Picker("Folder", selection: $selectedPreviewFolderID) {
                        Text("Choose Folder").tag(UUID?.none)
                        ForEach(model.configuration.folders) { folder in
                            Text(folder.name).tag(UUID?.some(folder.id))
                        }
                    }
                    HStack {
                        TextField("File to preview", text: $previewFilePath)
                        Button("Choose File") {
                            previewFilePath = PathPicker.chooseFile(initialPath: previewFilePath) ?? previewFilePath
                        }
                    }
                    Button("Preview Matching Rules") {
                        guard let selectedPreviewFolderID else { return }
                        Task {
                            await model.preview(folderID: selectedPreviewFolderID, filePath: previewFilePath)
                        }
                    }
                    .disabled(selectedPreviewFolderID == nil || previewFilePath.isEmpty)
                }
            }
            .navigationTitle("FolderAutomator")
        } detail: {
            detailView
        }
        .task {
            await model.load()
            selectedFolderID = model.configuration.folders.first?.id
            selectedPreviewFolderID = model.configuration.folders.first?.id
        }
    }

    @ViewBuilder
    private var detailView: some View {
        if showingPreferences {
            GeneralSettingsView(settings: $model.configuration.general)
                .padding(24)
        } else if let selectedFolderID,
           let folderIndex = model.configuration.folders.firstIndex(where: { $0.id == selectedFolderID }) {
            FolderEditorView(model: model, folder: $model.configuration.folders[folderIndex])
        } else {
            DefaultDetailPane(model: model)
        }
    }

    private func deleteFilteredFolders(at offsets: IndexSet) {
        let ids = offsets.compactMap { model.filteredFolders[safe: $0]?.id }
        let indices = ids.compactMap { id in
            model.configuration.folders.firstIndex(where: { $0.id == id })
        }
        model.removeFolders(at: IndexSet(indices))
        if let first = model.configuration.folders.first {
            selectedFolderID = first.id
        }
    }

    private func handleFolderDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil)
                else { return }
                Task { @MainActor in
                    let bookmark = try? BookmarkManager.shared.makeBookmark(for: url.path)
                    model.configuration.folders.append(
                        WatchedFolder(
                            name: url.lastPathComponent,
                            path: url.path,
                            bookmarkData: bookmark,
                            rules: []
                        )
                    )
                    selectedFolderID = model.configuration.folders.last?.id
                }
            }
            return true
        }
        return false
    }
}

struct FolderRow: View {
    let folder: WatchedFolder

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(folder.name)
                Spacer()
                if folder.isEnabled {
                    Text("Live")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.green.opacity(0.15)))
                }
            }
            Text(folder.path)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(folder.rules.count) rule\(folder.rules.count == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct DropFolderCardView: View {
    let isTargeted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Drop a folder here")
                .font(.headline)
            Text("Drag folders from Finder to create watched folders quickly.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isTargeted ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isTargeted ? Color.accentColor : Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
        )
    }
}

struct DefaultDetailPane: View {
    @ObservedObject var model: FolderAutomatorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DashboardCardView(model: model)
                RulePreviewCardView(items: model.previewItems)
                ReversibleActionsCardView(model: model)
            }
            .padding(28)
        }
    }
}

struct DashboardCardView: View {
    @ObservedObject var model: FolderAutomatorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Automation Status")
                .font(.title3.weight(.semibold))
            HStack {
                MetricPill(title: "Folders", value: "\(model.configuration.folders.count)")
                MetricPill(title: "Active", value: "\(model.configuration.folders.filter(\.isEnabled).count)")
                MetricPill(title: "Mode", value: model.configuration.general.dryRunMode ? "Dry Run" : "Live")
                MetricPill(title: "Undo", value: "\(model.undoOperations.count)")
            }
            Text(model.configuration.general.skipPreviouslyMatchedFiles ? "Processed-file tracking is enabled." : "Files may be reprocessed repeatedly.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(model.configuration.general.stopAfterFirstMatchPerFile ? "Global rule processing stops after the first match per file." : "Files can continue through multiple matching rules.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.12),
                            Color(nsColor: .controlBackgroundColor)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }
}

struct MetricPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.4))
        )
    }
}

struct ReversibleActionsCardView: View {
    @ObservedObject var model: FolderAutomatorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Undo Queue")
                    .font(.headline)
                Spacer()
                Button("Undo Last") {
                    Task { await model.undoLastOperation() }
                }
                .disabled(model.undoOperations.isEmpty)
            }
            if model.undoOperations.isEmpty {
                Text("Reversible file moves, copies, renames, tag changes, and trash operations will appear here.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.undoOperations.prefix(5)) { operation in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(operation.kind.rawValue.capitalized)
                            .font(.subheadline.weight(.semibold))
                        Text(operation.sourcePath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let destinationPath = operation.destinationPath {
                            Text(destinationPath)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }
}

struct RulePreviewCardView: View {
    let items: [ActivityItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rule Preview")
                .font(.headline)
            Text("Use the preview controls in the sidebar to test matches without changing files.")
                .foregroundStyle(.secondary)
            PreviewResultsView(items: items)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }
}

struct FolderEditorView: View {
    @ObservedObject var model: FolderAutomatorModel
    @Binding var folder: WatchedFolder

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Name", text: $folder.name)
                        HStack {
                            TextField("Path", text: $folder.path)
                            Button("Choose Folder") {
                                model.choosePath(for: folder.id)
                            }
                        }
                        Toggle("Enabled", isOn: $folder.isEnabled)
                        Toggle("Include subfolders", isOn: $folder.includeSubfolders)
                        if folder.bookmarkData == nil {
                            Text("Folder access is path-based until you reselect it with Choose Folder.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } label: {
                    Text("Folder")
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Rules")
                            .font(.title3.weight(.semibold))
                        Spacer()
                        Button("Add Rule") {
                            folder.rules.append(
                                Rule(
                                    name: "New Rule",
                                    conditions: [
                                        RuleCondition(kind: .name, operator: .contains, value: "invoice")
                                    ],
                                    actions: [
                                        RuleAction(kind: .addTag, value: "Needs Review")
                                    ]
                                )
                            )
                        }
                    }

                    ForEach($folder.rules) { $rule in
                        RuleEditorView(model: model, folderID: folder.id, rule: $rule)
                    }
                    .onDelete { offsets in
                        folder.rules.remove(atOffsets: offsets)
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle(folder.name)
    }
}

struct RuleEditorView: View {
    @ObservedObject var model: FolderAutomatorModel
    let folderID: UUID
    @Binding var rule: Rule
    @State private var draggedActionID: UUID?
    @State private var hoveredActionID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                TextField("Rule name", text: $rule.name)
                Toggle("Enabled", isOn: $rule.isEnabled)
                    .toggleStyle(.switch)
                    .frame(width: 130)
            }

            HStack {
                Picker("Match", selection: $rule.matchMode) {
                    ForEach(RuleMatchMode.allCases) { mode in
                        Text(mode.rawValue.capitalized).tag(mode)
                    }
                }
                Toggle("Stop after match", isOn: $rule.stopProcessingAfterMatch)
                Toggle("Run once per file", isOn: $rule.runOncePerFile)
            }

            if rule.actions.isEmpty || (rule.conditions.isEmpty && rule.conditionGroups.isEmpty) {
                Text("A rule needs at least one condition or condition group and one action.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Conditions")
                    .font(.headline)
                ForEach($rule.conditions) { $condition in
                    ConditionEditorRow(condition: $condition)
                }
                .onDelete { offsets in
                    rule.conditions.remove(atOffsets: offsets)
                }

                Button("Add Condition") {
                    rule.conditions.append(RuleCondition(kind: .fileExtension, operator: .equals, value: "jpg"))
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Condition Groups")
                        .font(.headline)
                    Button("Add Group") {
                        rule.conditionGroups.append(
                            RuleConditionGroup(
                                matchMode: .all,
                                conditions: [RuleCondition(kind: .name, operator: .contains, value: "2024")]
                            )
                        )
                    }
                }
                ForEach($rule.conditionGroups) { $group in
                    ConditionGroupEditorView(group: $group)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Actions")
                        .font(.headline)
                    Spacer()
                    Text("Drag to reorder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach($rule.actions) { $action in
                    ActionEditorRow(
                        model: model,
                        folderID: folderID,
                        ruleID: rule.id,
                        action: $action,
                        isDropTargeted: hoveredActionID == action.id
                    ) {
                        rule.actions.removeAll { $0.id == action.id }
                    }
                    .draggable(action.id.uuidString) {
                        ActionDragBadge(label: actionLabel(for: action.kind))
                            .onAppear {
                                draggedActionID = action.id
                            }
                    }
                    .dropDestination(for: String.self) { items, _ in
                        guard let sourceIDString = items.first,
                              let sourceID = UUID(uuidString: sourceIDString)
                        else {
                            return false
                        }
                        moveAction(from: sourceID, to: action.id)
                        hoveredActionID = nil
                        draggedActionID = nil
                        return true
                    } isTargeted: { isTargeted in
                        hoveredActionID = isTargeted ? action.id : nil
                    }
                }

                Button("Add Action") {
                    rule.actions.append(RuleAction(kind: .move, value: ("~/Desktop/Sorted" as NSString).expandingTildeInPath))
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func moveAction(from sourceID: UUID, to destinationID: UUID) {
        guard sourceID != destinationID,
              let sourceIndex = rule.actions.firstIndex(where: { $0.id == sourceID }),
              let destinationIndex = rule.actions.firstIndex(where: { $0.id == destinationID })
        else {
            return
        }

        let adjustedDestination = sourceIndex < destinationIndex ? destinationIndex + 1 : destinationIndex
        rule.actions.move(fromOffsets: IndexSet(integer: sourceIndex), toOffset: adjustedDestination)
    }

    private func actionLabel(for kind: RuleActionKind) -> String {
        switch kind {
        case .move: return "Move"
        case .copy: return "Copy"
        case .rename: return "Rename"
        case .addTag: return "Add Finder Tag"
        case .trash: return "Trash"
        case .delete: return "Delete Permanently"
        case .shellScript: return "Shell Script"
        case .sortIntoSubfolder: return "Sort Into Subfolder"
        case .revealInFinder: return "Reveal In Finder"
        case .appendDateToName: return "Append Date"
        case .notify: return "Notify"
        case .openWithDefaultApp: return "Open With Default App"
        }
    }
}

struct ConditionGroupEditorView: View {
    @Binding var group: RuleConditionGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Group Match", selection: $group.matchMode) {
                ForEach(RuleMatchMode.allCases) { mode in
                    Text(mode.rawValue.capitalized).tag(mode)
                }
            }
            ForEach($group.conditions) { $condition in
                ConditionEditorRow(condition: $condition)
            }
            .onDelete { offsets in
                group.conditions.remove(atOffsets: offsets)
            }
            Button("Add Group Condition") {
                group.conditions.append(RuleCondition(kind: .name, operator: .contains, value: "receipt"))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.5))
        )
    }
}

struct ConditionEditorRow: View {
    @Binding var condition: RuleCondition

    var body: some View {
        HStack {
            Picker("Field", selection: $condition.kind) {
                ForEach(RuleConditionKind.allCases) { kind in
                    Text(label(for: kind)).tag(kind)
                }
            }
            Picker("Operator", selection: $condition.operator) {
                ForEach(operators(for: condition.kind)) { op in
                    Text(label(for: op)).tag(op)
                }
            }
            TextField(valuePlaceholder(for: condition.kind), text: $condition.value)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func operators(for kind: RuleConditionKind) -> [ConditionOperator] {
        switch kind {
        case .name, .fileExtension, .tag, .sourceFolder, .uniformType, .contentContains, .archiveEntryName:
            return [.contains, .equals, .startsWith, .endsWith, .notContains, .matchesRegex]
        case .contentMatchesRegex:
            return [.matchesRegex]
        case .fileSizeMB, .imageWidth, .imageHeight:
            return [.greaterThan, .lessThan, .equals]
        case .createdDate, .modifiedDate, .filenameDate:
            return [.olderThanDays, .newerThanDays]
        case .isDirectory, .isImage, .isAudio, .isVideo, .duplicateFileName, .duplicateContentHash:
            return [.isTrue]
        }
    }

    private func label(for op: ConditionOperator) -> String {
        switch op {
        case .contains:
            return "contains"
        case .equals:
            return "equals"
        case .greaterThan:
            return ">"
        case .lessThan:
            return "<"
        case .startsWith:
            return "starts with"
        case .endsWith:
            return "ends with"
        case .notContains:
            return "does not contain"
        case .matchesRegex:
            return "regex"
        case .olderThanDays:
            return "older than days"
        case .newerThanDays:
            return "newer than days"
        case .isTrue:
            return "is true"
        }
    }

    private func label(for kind: RuleConditionKind) -> String {
        switch kind {
        case .name: return "Name"
        case .fileExtension: return "Extension"
        case .fileSizeMB: return "Size (MB)"
        case .createdDate: return "Created Date"
        case .modifiedDate: return "Modified Date"
        case .tag: return "Finder Tag"
        case .sourceFolder: return "Source Folder"
        case .isDirectory: return "Is Directory"
        case .isImage: return "Is Image"
        case .isAudio: return "Is Audio"
        case .isVideo: return "Is Video"
        case .uniformType: return "Uniform Type"
        case .contentContains: return "Contents"
        case .contentMatchesRegex: return "Content Regex"
        case .duplicateFileName: return "Duplicate Filename"
        case .duplicateContentHash: return "Duplicate Content"
        case .archiveEntryName: return "Archive Entry"
        case .filenameDate: return "Filename Date"
        case .imageWidth: return "Image Width"
        case .imageHeight: return "Image Height"
        }
    }

    private func valuePlaceholder(for kind: RuleConditionKind) -> String {
        switch kind {
        case .archiveEntryName:
            return "Invoices/"
        case .contentMatchesRegex:
            return "invoice\\s+#\\d+"
        case .filenameDate:
            return "30"
        case .imageWidth, .imageHeight:
            return "1920"
        default:
            return "Value"
        }
    }
}

struct ActionEditorRow: View {
    @ObservedObject var model: FolderAutomatorModel
    let folderID: UUID
    let ruleID: UUID
    @Binding var action: RuleAction
    let isDropTargeted: Bool
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)
                Picker("Action", selection: $action.kind) {
                    ForEach(RuleActionKind.allCases) { kind in
                        Text(label(for: kind)).tag(kind)
                    }
                }
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                }
                .help("Remove Action")
            }
            actionValueEditor
            if supportsConflictPolicy(action.kind) {
                Picker(conflictLabel(for: action.kind), selection: $action.conflictPolicy) {
                    ForEach(ConflictPolicy.allCases) { policy in
                        Text(conflictPolicyLabel(policy)).tag(policy)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isDropTargeted ? Color.accentColor.opacity(0.12) : Color.white.opacity(0.55))
        )
    }

    @ViewBuilder
    private var actionValueEditor: some View {
        switch action.kind {
        case .shellScript:
            VStack(alignment: .leading, spacing: 8) {
                Picker("Source", selection: $action.shellScriptSource) {
                    Text("Inline").tag(ShellScriptSource.inline)
                    Text("Script File").tag(ShellScriptSource.file)
                }
                .pickerStyle(.segmented)

                switch action.shellScriptSource {
                case .inline:
                    TextEditor(text: $action.value)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 96)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.secondary.opacity(0.25))
                        )
                    Text("Available env vars: OPEN_HAZEL_FILE_PATH and OPEN_HAZEL_FILE_NAME")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .file:
                    HStack {
                        TextField("/path/to/script.sh", text: $action.value)
                            .textFieldStyle(.roundedBorder)
                        Button("Choose Script") {
                            model.chooseActionPath(folderID: folderID, ruleID: ruleID, actionID: action.id)
                        }
                    }
                }

                Toggle("Use file location as working directory", isOn: $action.useFileLocationAsWorkingDirectory)

                if action.useFileLocationAsWorkingDirectory == false {
                    HStack {
                        TextField("/path/to/working-directory", text: $action.shellScriptWorkingDirectoryPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Choose Folder") {
                            model.chooseActionWorkingDirectory(folderID: folderID, ruleID: ruleID, actionID: action.id)
                        }
                    }
                }

                Text(action.useFileLocationAsWorkingDirectory
                    ? "The script runs in the matched file's folder."
                    : "The script runs in the selected working directory.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        default:
            HStack {
                TextField(placeholder(for: action.kind), text: $action.value)
                    .textFieldStyle(.roundedBorder)
                if action.kind == .move || action.kind == .copy {
                    Button("Choose") {
                        model.chooseActionPath(folderID: folderID, ruleID: ruleID, actionID: action.id)
                    }
                }
            }
        }
    }

    private func label(for kind: RuleActionKind) -> String {
        switch kind {
        case .move: return "Move"
        case .copy: return "Copy"
        case .rename: return "Rename"
        case .addTag: return "Add Finder Tag"
        case .trash: return "Trash"
        case .delete: return "Delete Permanently"
        case .shellScript: return "Shell Script"
        case .sortIntoSubfolder: return "Sort Into Subfolder"
        case .revealInFinder: return "Reveal In Finder"
        case .appendDateToName: return "Append Date"
        case .notify: return "Notify"
        case .openWithDefaultApp: return "Open With Default App"
        }
    }

    private func placeholder(for kind: RuleActionKind) -> String {
        switch kind {
        case .move, .copy:
            return "/path/to/folder"
        case .rename:
            return "{date}-{name}-{filenameDate}.{ext}"
        case .addTag:
            return "Finder tag"
        case .trash, .delete:
            return "No value needed"
        case .shellScript:
            return "echo \"$OPEN_HAZEL_FILE_PATH\""
        case .sortIntoSubfolder:
            return "Images"
        case .revealInFinder:
            return "No value needed"
        case .appendDateToName:
            return "No value needed"
        case .notify:
            return "Rule matched"
        case .openWithDefaultApp:
            return "No value needed"
        }
    }

    private func supportsConflictPolicy(_ kind: RuleActionKind) -> Bool {
        [.move, .copy, .rename, .sortIntoSubfolder, .appendDateToName].contains(kind)
    }

    private func conflictLabel(for kind: RuleActionKind) -> String {
        switch kind {
        case .move:
            return "If destination exists"
        case .copy:
            return "If copy exists"
        case .rename, .sortIntoSubfolder, .appendDateToName:
            return "If target exists"
        default:
            return "Conflict"
        }
    }

    private func conflictPolicyLabel(_ policy: ConflictPolicy) -> String {
        switch policy {
        case .unique:
            return "Keep Both"
        case .replace:
            return "Overwrite"
        case .skip:
            return "Skip"
        }
    }
}

struct ActionDragBadge: View {
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
            Text(label)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }
}

struct GeneralSettingsView: View {
    @Binding var settings: GeneralSettings

    var body: some View {
        Form {
            Toggle("Run rules automatically", isOn: $settings.runRulesAutomatically)
            Toggle("Process existing files on launch", isOn: $settings.processExistingFilesOnLaunch)
            Toggle("Ignore hidden files", isOn: $settings.ignoreHiddenFiles)
            Toggle("Launch runner at login", isOn: $settings.launchAtLogin)
            Toggle("Dry-run mode", isOn: $settings.dryRunMode)
            Toggle("Skip previously matched files", isOn: $settings.skipPreviouslyMatchedFiles)
            Toggle("Stop after first match per file", isOn: $settings.stopAfterFirstMatchPerFile)
            Stepper(value: $settings.maxActivityItems, in: 25...1_000, step: 25) {
                Text("Stored activity items: \(settings.maxActivityItems)")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Preferences")
    }
}

@MainActor
public struct ActivityListView: View {
    @ObservedObject var model: FolderAutomatorModel

    public init(model: FolderAutomatorModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search activity", text: $model.activitySearchText)
                Button("Undo Last") {
                    Task { await model.undoLastOperation() }
                }
                .disabled(model.undoOperations.isEmpty)
            }
            .padding()

            List(model.filteredActivity) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.message)
                    if let ruleName = item.ruleName {
                        Text(ruleName)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                    }
                    if let filePath = item.filePath {
                        Text(filePath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let undoSummary = item.undoSummary {
                        Text("Undo: \(undoSummary)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(item.timestamp.formatted(date: .abbreviated, time: .standard))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .overlay {
                if model.filteredActivity.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "folder.badge.questionmark")
                            .font(.system(size: 30))
                            .foregroundStyle(.secondary)
                        Text("No Activity Yet")
                            .font(.headline)
                        Text("Rule matches and execution events will appear here.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct PreviewResultsView: View {
    let items: [ActivityItem]

    var body: some View {
        GroupBox {
            if items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No preview yet")
                        .font(.headline)
                    Text("Pick a folder and file in the sidebar to simulate matching rules.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(items) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.message)
                                if let undoSummary = item.undoSummary {
                                    Text("Undo: \(undoSummary)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
