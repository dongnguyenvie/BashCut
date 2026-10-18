import AppKit
import BashCutAutomation
import BashCutDocument
import BashCutProject
import SwiftUI

private final class BatchWindowDelegate: NSObject, NSWindowDelegate {
    let closed: () -> Void
    init(closed: @escaping () -> Void) { self.closed = closed }
    func windowWillClose(_ notification: Notification) { closed() }
}

/// The batch runner window (P2-C2): the pipeline being built (inputs, steps, the selected step's settings), saved as a
/// preset and run with the app-wide `BatchRunner`; the queue under it follows the run. The user's Run click is the
/// batch's approval, so a run started here does not ask again.
@MainActor @Observable final class BatchWindowModel {
    unowned let document: ProjectDocument
    var pipeline = BatchPipeline(inputs: [], steps: [])
    var selectedStep: Int?
    /// The run the queue shows: the one started here, else the latest.
    var runID: String?
    var message = ""
    private(set) var presets: [BatchPipeline] = []
    /// What the inputs expand to, and why they do not when one is missing.
    private(set) var items: [BatchItemSource] = []
    private(set) var itemsError: String?
    private(set) var isOpen = false
    /// True while the checks before a run (keys, files, disk) are going.
    private(set) var checking = false
    @ObservationIgnored private var window: NSWindow?
    @ObservationIgnored private var delegate: BatchWindowDelegate?

    init(document: ProjectDocument) { self.document = document }

    var run: BatchRunStatus? { runID.flatMap(document.batches.run) ?? document.batches.runs.last }
    var running: Bool { run.map { !$0.state.isFinished } ?? false }

    // MARK: Window

    /// Shows the window; with `step`, that step goes first in the pipeline (a tool card's "Many projects / files…"),
    /// replacing a first step of the same action.
    func open(firstStep step: BatchStep? = nil) {
        if let step {
            if pipeline.steps.first?.action == step.action { pipeline.steps[0] = step } else { pipeline.steps.insert(step, at: 0) }
            selectedStep = 0
        }
        reloadPresets()
        refreshItems()
        isOpen = true
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = AuxiliaryWindow.make(
            title: String(localized: "Batch"), size: NSSize(width: 1180, height: 760),
            minSize: NSSize(width: 980, height: 600),
            content: BatchWindowView(model: self, pluginManager: document.plugins))
        let delegate = BatchWindowDelegate { [weak self] in
            self?.window = nil
            self?.delegate = nil
            self?.isOpen = false
        }
        self.delegate = delegate
        window.delegate = delegate
        self.window = window
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func close() { window?.close() }

    // MARK: Inputs

    /// Adds files, folders or projects (a project file or its folder), each once.
    func addInputs(_ urls: [URL]) {
        let known = Set(pipeline.inputs.map(\.path))
        for url in urls where !known.contains(url.standardizedFileURL.path) {
            pipeline.inputs.append(BatchInput(path: url.standardizedFileURL.path))
        }
        refreshItems()
    }

    func chooseInputs() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.message = String(localized: "Choose videos, a folder or projects")
        guard let urls = ModalCenter.shared.open(panel, name: "batch-inputs") else { return }
        addInputs(urls)
    }

    func removeInput(_ index: Int) {
        guard pipeline.inputs.indices.contains(index) else { return }
        pipeline.inputs.remove(at: index)
        refreshItems()
    }

    func refreshItems() {
        do {
            items = try pipeline.items()
            itemsError = nil
        } catch {
            items = []
            itemsError = pipeline.inputs.isEmpty ? nil : BatchMessage.localized(error.localizedDescription)
        }
    }

    // MARK: Steps

    func addStep(_ action: String, label: String? = nil) {
        pipeline.steps.append(BatchRunner.newStep(action, label: label, pipeline: pipeline))
        selectedStep = pipeline.steps.count - 1
    }

    func removeStep(_ index: Int) {
        guard pipeline.steps.indices.contains(index) else { return }
        pipeline.steps.remove(at: index)
        selectedStep = pipeline.steps.isEmpty ? nil : min(index, pipeline.steps.count - 1)
    }

    func moveStep(_ index: Int, by offset: Int) {
        let target = index + offset
        guard pipeline.steps.indices.contains(index), pipeline.steps.indices.contains(target) else { return }
        pipeline.steps.swapAt(index, target)
        selectedStep = target
    }

    func setLabel(_ index: Int, _ label: String?) {
        guard pipeline.steps.indices.contains(index) else { return }
        pipeline.steps[index].label = label
    }

    /// The selected step's parameter `name`, nil when unset.
    func parameter(_ name: String) -> JSONValue? {
        guard let index = selectedStep, pipeline.steps.indices.contains(index) else { return nil }
        return pipeline.steps[index].params[name]
    }

    func setParameter(_ name: String, _ value: JSONValue?) {
        guard let index = selectedStep, pipeline.steps.indices.contains(index) else { return }
        pipeline.steps[index].params[name] = value
    }

    /// A step's title for the list and the queue: its label, else the tool or command it runs.
    func title(_ step: BatchStep) -> String {
        if let label = step.label {
            // A catalog title kept as the label (CLI pipelines, presets) is the default, shown in the app's language.
            if let entry = BatchStepCatalog.entry(step.action), entry.title == label { return entry.localizedTitle }
            return label
        }
        if step.action == BatchRunner.exportAction { return String(localized: "Export") }
        return document.plugins.action(step.action)?.title ?? step.action
    }

    // MARK: Presets

    func reloadPresets() { presets = document.batchPresets.list() }

    /// Saves the pipeline under its name, without its inputs (they are given each run).
    func savePreset() {
        var preset = pipeline
        preset.name = pipeline.name?.trimmingCharacters(in: .whitespaces)
        guard let name = preset.name, !name.isEmpty else {
            message = String(localized: "Name the pipeline to save it as a preset")
            return
        }
        preset.inputs = []
        var checked = preset
        checked.inputs = [BatchInput(path: "/")]
        do {
            try BatchRunner.check(checked) { [plugins = document.plugins] in plugins.action($0) != nil }
            try document.batchPresets.save(preset)
            message = String(format: String(localized: "Saved preset %@"), name)
        } catch { message = BatchMessage.localized(error.localizedDescription) }
        reloadPresets()
    }

    /// Loads a preset's steps and settings, keeping the inputs when the preset has none.
    func loadPreset(_ preset: BatchPipeline) {
        let inputs = pipeline.inputs
        pipeline = preset
        if pipeline.inputs.isEmpty { pipeline.inputs = inputs }
        selectedStep = pipeline.steps.isEmpty ? nil : 0
        message = ""
        refreshItems()
    }

    // MARK: Running

    /// Checks the pipeline and starts it: the click is the approval. The checks before a run (keys, files, disk)
    /// may ask first; an unsaved open project is saved or discarded first, as the user chooses.
    func start() {
        message = ""
        document.markDeniedBatches()
        if let active = document.batches.active {
            message = String(format: String(localized: "Batch %@ is still running"), active.id)
            return
        }
        var items: [BatchItemSource]
        do {
            try BatchRunner.check(pipeline) { [plugins = document.plugins] in plugins.action($0) != nil }
            items = try pipeline.items()
        } catch {
            message = BatchMessage.localized(RPCFailure.from(error).message)
            return
        }
        let pipeline = pipeline
        afterPreflight(pipeline, items: items) { [self] skipped in
            items = items.enumerated().filter { !skipped.contains($0.offset) }.map(\.element)
            guard !items.isEmpty, let leave = leaveCurrent() else { return }
            let id = document.batches.add(pipeline, items: items, awaitingApproval: false)
            runID = id
            document.batches.start(id, host: DocumentBatchHost(document: document, author: .user), author: .user, leave: leave)
            DebugLog.write("batch", "\(id) started from the batch window: \(items.count) items, \(pipeline.steps.count) steps")
        }
    }

    /// Runs the queue's failed, cancelled, skipped or interrupted items again (`indices`, default all of them), each
    /// from the step that did not complete, in the project it made. The click is the approval.
    func retry(_ indices: [Int]? = nil) {
        message = ""
        document.markDeniedBatches()
        guard document.batches.active == nil, let run, !run.retryableItems.isEmpty else { return }
        do {
            try BatchRunner.check(ProjectDocument.presetCheckCopy(run.pipeline)) { [plugins = document.plugins] in
                plugins.action($0) != nil
            }
        } catch {
            message = BatchMessage.localized(RPCFailure.from(error).message)
            return
        }
        let chosen = indices ?? run.retryableItems
        afterPreflight(run.pipeline, items: chosen.map { run.items[$0].source }) { [self] skipped in
            let remaining = chosen.enumerated().filter { !skipped.contains($0.offset) }.map(\.element)
            guard !remaining.isEmpty, let leave = leaveCurrent() else { return }
            runID = run.id
            document.batches.retry(run.id, items: remaining, host: DocumentBatchHost(document: document, author: .user),
                                   author: .user, leave: leave)
            DebugLog.write("batch", "\(run.id) retried from the batch window: \(remaining.count) items")
        }
    }

    /// Runs the checks before a run, then `proceed` with the indices of `items` to leave out ("Run without them" for
    /// files that do not read), unless the user cancelled. Asks only when something was found. The alerts (this one
    /// and the unsaved-project one in `proceed`) open from the run loop like a click, not from the checks' task: a
    /// modal loop inside a task would hold the main queue, and with it the batch and every automation call.
    private func afterPreflight(
        _ pipeline: BatchPipeline, items: [BatchItemSource], proceed: @escaping @MainActor (Set<Int>) -> Void
    ) {
        checking = true
        message = String(localized: "Checking keys, files and disk space…")
        Task {
            let issues = await BatchPreflight.check(pipeline, items: items, document: document)
            checking = false
            message = ""
            RunLoop.main.perform(inModes: [.default]) {
                MainActor.assumeIsolated {
                    if let skipped = self.answerPreflight(issues, items: items) { proceed(skipped) }
                }
            }
        }
    }

    /// Nil when the user cancelled, else the items to leave out.
    private func answerPreflight(_ issues: [BatchPreflightIssue], items: [BatchItemSource]) -> Set<Int>? {
        guard !issues.isEmpty else { return [] }
        let unreadable = issues.compactMap { issue -> [Int]? in
            if case .files(let indices) = issue.kind { return indices }
            return nil
        }.first ?? []
        let needsKey = issues.contains { if case .key = $0.kind { true } else { false } }
        var buttons: [ModalOption] = []
        if !unreadable.isEmpty, unreadable.count < items.count {
            buttons.append(ModalOption("without", String(format: String(localized: "Skip Them, Run %lld"),
                                                         items.count - unreadable.count)))
        }
        buttons.append(ModalOption("run", String(localized: "Run Anyway")))
        if needsKey { buttons.append(ModalOption("settings", String(localized: "Open Plugin Settings"))) }
        buttons.append(ModalOption("cancel", String(localized: "Cancel")))
        switch ModalCenter.shared.alert(
            "batch-preflight", title: String(localized: "Check before the batch runs"),
            message: issues.map { "• " + $0.localized }.joined(separator: "\n"), buttons: buttons)
        {
        case "without": return Set(unreadable)
        case "run": return []
        case "settings":
            document.ui.settingsSection = "plugins"
            document.ui.showSettings = true
            NSApp.windows.first { $0.contentView is NSHostingView<EditorView> }?.makeKeyAndOrderFront(nil)
            return nil
        default: return nil
        }
    }

    /// How the first item leaves the open project: nil when the user cancelled.
    private func leaveCurrent() -> [String: JSONValue]? {
        guard document.dirty else { return [:] }
        var buttons = [ModalOption("discard", String(localized: "Discard and Run")), ModalOption("cancel", String(localized: "Cancel"))]
        if document.fileURL != nil { buttons.insert(ModalOption("save", String(localized: "Save and Run")), at: 0) }
        switch ModalCenter.shared.alert(
            "batch-unsaved", title: String(localized: "The open project has unsaved changes"),
            message: String(localized: "The batch opens each item's project in the editor."), buttons: buttons)
        {
        case "save": return ["saveCurrent": .bool(true)]
        case "discard": return ["discardCurrent": .bool(true)]
        default: return nil
        }
    }

    func cancel() {
        guard let run, !run.state.isFinished else { return }
        document.batches.cancel(run.id, jobs: document.jobs)
    }

    /// Opens the item's project in the editor, to fix it. Not while the batch runs: it switches projects itself.
    func openItem(_ index: Int) {
        guard !running, let project = run?.items[safe: index]?.project else { return }
        document.openProject(at: project)
        let editor = NSApp.windows.first { $0.contentView is NSHostingView<EditorView> }
        editor?.makeKeyAndOrderFront(nil)
    }

    /// Shows the item's exports in Finder, else its project.
    func revealItem(_ index: Int) {
        guard let item = run?.items[safe: index] else { return }
        let files = item.outputs.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        let urls = files.isEmpty ? [item.project?.deletingLastPathComponent() ?? item.source.url] : files
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}

extension BatchStepCatalog.Entry {
    /// The catalog's English title, localized here (the core list has no strings of its own).
    var localizedTitle: String { String(localized: String.LocalizationValue(title)) }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
