import BashCutAutomation
import BashCutDocument
import BashCutProject
import SwiftUI
import UniformTypeIdentifiers

/// The batch runner window (P2-C2): inputs, pipeline steps and the selected step's settings in three columns, the queue
/// of the run under them. Everything a run needs is built, saved and started here.
struct BatchWindowView: View {
    @Bindable var model: BatchWindowModel
    @Bindable var pluginManager: PluginManagerModel

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            HStack(spacing: 0) {
                BatchInputsColumn(model: model).frame(width: 290)
                Divider()
                BatchPipelineColumn(model: model).frame(width: 310)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let index = model.selectedStep, model.pipeline.steps.indices.contains(index) {
                            BatchStepCard(model: model, index: index)
                                .id("\(index)/\(model.pipeline.steps[index].action)")
                        } else {
                            Text("Add a step, or select one to change its settings.").foregroundStyle(.secondary)
                        }
                        Divider()
                        BatchSettingsSection(model: model)
                    }
                    .padding(14)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)
            Divider()
            BatchQueueView(model: model).frame(height: 230)
        }
        .frame(minWidth: 980, minHeight: 600)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label("Batch", systemImage: "gearshape.2").font(.headline)
            TextField("Pipeline name", text: Binding(
                get: { model.pipeline.name ?? "" }, set: { model.pipeline.name = $0.isEmpty ? nil : $0 }))
                .textFieldStyle(.roundedBorder).frame(width: 220)
            Menu("Presets") {
                if model.presets.isEmpty { Text("No saved presets") }
                ForEach(model.presets, id: \.name) { preset in
                    Button(preset.name ?? "") { model.loadPreset(preset) }
                }
            }
            .fixedSize()
            .accessibilityIdentifier("batch-presets")
            if !model.message.isEmpty {
                Text(model.message).font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
            }
            Spacer(minLength: 8)
            Button("Save Preset", action: model.savePreset)
                .disabled(model.pipeline.steps.isEmpty)
                .accessibilityIdentifier("batch-save-preset")
            if model.running {
                Button("Cancel Batch", role: .destructive, action: model.cancel).accessibilityIdentifier("batch-cancel")
            } else {
                Button(model.items.count == 1 ? String(localized: "Run 1 item")
                       : String(format: String(localized: "Run %lld items"), model.items.count), action: model.start)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.items.isEmpty || model.pipeline.steps.isEmpty || model.checking)
                    .accessibilityIdentifier("batch-run")
            }
        }
    }
}

/// Inputs: the drop zone, Add…, and each input with what it becomes.
private struct BatchInputsColumn: View {
    @Bindable var model: BatchWindowModel
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Inputs").font(.headline)
                Text(verbatim: "\(model.items.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Button("Add…", action: model.chooseInputs).accessibilityIdentifier("batch-add-inputs")
            }
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .foregroundStyle(targeted ? Color.cyan : Color.secondary.opacity(0.5))
                .overlay {
                    Text("Drop videos, a folder or projects here").font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(8)
                }
                .frame(height: 70)
                .contentShape(Rectangle())
                .onTapGesture(perform: model.chooseInputs)
                .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
                    Task { @MainActor in model.addInputs(await Self.urls(providers)) }
                    return true
                }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(model.pipeline.inputs.enumerated()), id: \.offset) { index, input in
                        inputRow(index, input)
                    }
                }
            }
            if let error = model.itemsError {
                Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            } else if !model.items.isEmpty {
                let files = model.items.filter { $0.kind == .file }.count
                Text("\(files) new projects from files, \(model.items.count - files) existing projects")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
    }

    private func inputRow(_ index: Int, _ input: BatchInput) -> some View {
        let url = URL(fileURLWithPath: input.path)
        let isProject = BatchPipeline.detectedKindIsProject(url)
        var isFolder: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder)
        return HStack(spacing: 6) {
            Image(systemName: isProject ? "film.stack" : isFolder.boolValue ? "folder" : "film").frame(width: 16)
            Text(verbatim: isProject && url.lastPathComponent == BatchPipeline.projectFileName
                 ? url.deletingLastPathComponent().lastPathComponent : url.lastPathComponent)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            Text(isProject ? "project" : isFolder.boolValue ? "folder" : "file").font(.caption2).foregroundStyle(.secondary)
            Button { model.removeInput(index) } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Remove")
        }
        .padding(.vertical, 3).help(input.path)
    }

    private static func urls(_ providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? URL {
                urls.append(url)
            } else if let data = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? Data,
                let url = URL(dataRepresentation: data, relativeTo: nil)
            {
                urls.append(url)
            }
        }
        return urls
    }
}

extension BatchPipeline {
    /// Whether `url` is a project (its file or folder), for the inputs list.
    static func detectedKindIsProject(_ url: URL) -> Bool {
        url.lastPathComponent == projectFileName
            || FileManager.default.fileExists(atPath: url.appendingPathComponent(projectFileName).path)
    }
}

/// The ordered steps and "＋ Add step", which lists the tools first, then the export step, every command a batch may
/// run (by area) and the plugin actions.
private struct BatchPipelineColumn: View {
    @Bindable var model: BatchWindowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pipeline").font(.headline)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(model.pipeline.steps.enumerated()), id: \.offset) { index, step in
                        stepRow(index, step)
                    }
                }
            }
            addStepMenu
        }
        .padding(14)
    }

    private func stepRow(_ index: Int, _ step: BatchStep) -> some View {
        let selected = model.selectedStep == index
        let plugin = model.document.plugins.action(step.action)
        return HStack(spacing: 8) {
            Text(verbatim: "\(index + 1)").font(.caption.monospacedDigit()).frame(width: 18)
                .padding(3).background(Circle().fill(Color.white.opacity(0.08)))
            Text(verbatim: model.title(step)).lineLimit(1)
            Spacer(minLength: 4)
            Text(verbatim: plugin?.plugin.manifest.displayName ?? String(localized: "built-in"))
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            if selected {
                Button { model.moveStep(index, by: -1) } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(.plain).disabled(index == 0).help("Move up")
                Button { model.moveStep(index, by: 1) } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(.plain).disabled(index == model.pipeline.steps.count - 1).help("Move down")
                Button { model.removeStep(index) } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain).help("Remove step")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(selected ? Color.cyan.opacity(0.14) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture { model.selectedStep = index }
        .foregroundStyle(selected ? Color.cyan : Color.primary)
        .accessibilityIdentifier("batch-step-\(index + 1)")
    }

    private var addStepMenu: some View {
        let document = model.document
        let areas = Dictionary(grouping: BatchRunner.stepCommands) { $0.cliWords.first ?? "" }
        return Menu {
            ForEach(BatchStepCatalog.Group.allCases, id: \.self) { group in
                Section(Self.title(group)) {
                    ForEach(BatchStepCatalog.entries.filter { $0.group == group }, id: \.action) { entry in
                        Button(entry.localizedTitle) { model.addStep(entry.action, label: entry.localizedTitle) }
                    }
                }
            }
            Section("Tools") {
                ForEach(document.toolEntries) { tool in
                    if let action = Self.stepAction(tool) {
                        Button(tool.title) { model.addStep(action, label: tool.title) }
                    }
                }
            }
            Section("Commands") {
                ForEach(areas.keys.sorted(), id: \.self) { area in
                    Menu(area) {
                        ForEach(areas[area] ?? [], id: \.name) { spec in
                            Button(spec.cliWords.joined(separator: " ")) { model.addStep(spec.name) }.help(spec.summary)
                        }
                    }
                }
            }
            let actions = document.plugins.actions
            if !actions.isEmpty {
                Section("Plugin actions") {
                    ForEach(actions, id: \.id) { action in
                        Button("\(action.title) · \(action.plugin.manifest.displayName)") {
                            model.addStep(action.id, label: action.title)
                        }
                    }
                }
            }
        } label: {
            Label("Add step", systemImage: "plus")
        }
        .accessibilityIdentifier("batch-add-step")
    }

    static func title(_ group: BatchStepCatalog.Group) -> String {
        switch group {
        case .build: String(localized: "Build")
        case .fix: String(localized: "Fix")
        case .check: String(localized: "Check")
        case .export: String(localized: "Export")
        }
    }

    private static func stepAction(_ tool: ToolListEntry) -> String? {
        switch tool.source {
        case .native: BatchRunner.stepAction(forTool: tool.id)
        case .action(let id): id
        case .view: nil
        }
    }
}

/// What the whole batch shares: the template each file's project starts from, the failure policy, the export file
/// names and the items asked to run at once.
private struct BatchSettingsSection: View {
    @Bindable var model: BatchWindowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Batch settings").font(.headline)
            Text("Each file becomes a new project from this template, so every result can be opened and fixed.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Picker("Canvas", selection: Binding(
                get: { model.pipeline.template.canvas ?? "auto" },
                set: { model.pipeline.template.canvas = $0 == "auto" ? nil : $0 })
            ) {
                Text("From the first clip").tag("auto")
                Text("Portrait 9:16").tag("portrait")
                Text("Landscape 16:9").tag("landscape")
                Text("Square 1:1").tag("square")
            }
            LabeledContent("New projects in") {
                HStack {
                    Text(verbatim: model.pipeline.projectsFolder.map { ($0 as NSString).abbreviatingWithTildeInPath }
                         ?? String(localized: "The projects folder"))
                        .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                    Button("Choose…") { chooseProjectsFolder() }
                }
            }
            Picker("If a step fails", selection: $model.pipeline.onFailure) {
                Text("Skip the item, continue").tag(BatchFailurePolicy.skipItem)
                Text("Stop the batch").tag(BatchFailurePolicy.stop)
            }
            LabeledContent("Output name") {
                TextField(BatchPipeline.defaultOutputName, text: $model.pipeline.outputName).textFieldStyle(.roundedBorder)
            }
            .help("Export file names: {name}, {preset}, {index}, {pipeline}")
            Stepper(value: $model.pipeline.concurrency, in: 1...BatchPipeline.maximumConcurrency) {
                Text("Run at once: \(model.pipeline.concurrency)")
            }
            .help("Items run one at a time today, in the open editor; the value is kept for later.")
        }
    }

    private func chooseProjectsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        guard let url = ModalCenter.shared.open(panel, name: "batch-projects-folder")?.first else { return }
        model.pipeline.projectsFolder = url.path
    }
}
