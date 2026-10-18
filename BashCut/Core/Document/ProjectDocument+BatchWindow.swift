import BashCutDocument
import BashCutProject
import Foundation

/// The batch runner window (P2-C2): File ▸ Batch…, `ui action open batch`, and a tool card's "Run on › Many projects /
/// files…", which opens it with that tool as the first step. Agents read and drive it as the `batch` window dialog.
extension ProjectDocument {
    func openBatch(_ firstStep: BatchStep? = nil) {
        batchWindow.open(firstStep: firstStep)
    }

    /// At launch: a batch BashCut quit (or stopped) during comes back interrupted; offer to resume its items.
    func offerBatchResume() {
        guard batches.active == nil, let run = batches.runs.last, run.state == .interrupted, !run.retryableItems.isEmpty,
            ModalCenter.shared.current == nil
        else { return }
        let done = run.count(.completed)
        let answer = ModalCenter.shared.alert(
            "batch-resume", title: String(localized: "A batch was interrupted"),
            message: String(format: String(localized: "%@: %lld of %lld items done, %lld left. Resume it now?"),
                            run.pipeline.name ?? run.id, done, run.items.count, run.retryableItems.count),
            buttons: [ModalOption("resume", String(localized: "Resume")), ModalOption("show", String(localized: "Show Batch")),
                      ModalOption("later", String(localized: "Later"))],
            style: .informational)
        guard answer != "later" else { return }
        batchWindow.runID = run.id
        batchWindow.open()
        if answer == "resume" { batchWindow.retry() }
    }

    /// The window as a dialog (`ui dialog`, `ui respond --dialog sheet:batch`): the pipeline in the message, and Add
    /// inputs, Add step (`add-step:<action>`), Remove and Move for each step, Load for each saved preset, Save preset,
    /// Run, Cancel, and Open/Reveal for each finished item of the queue.
    func batchWindowSheet() -> ModalSheet? {
        let model = batchWindow
        guard model.isOpen else { return nil }
        var options = [BatchWindowOption.addInputs]
        if !model.running {
            options += BatchWindowOption.editing(steps: model.pipeline.steps.count,
                                                 presets: batchPresets.list().compactMap(\.name))
        }
        options += [.savePreset, model.running ? .cancel : .run]
        let finished = model.run?.items.enumerated().filter { $0.element.project != nil && $0.element.state.isFinished } ?? []
        if !model.running {
            for (index, _) in finished { options += [.openItem(index + 1), .revealItem(index + 1)] }
        }
        options.append(.close)
        return ModalSheet(name: "batch", title: "Batch", message: batchWindowSummary(),
                          options: options.map { ModalOption($0.id, batchOptionTitle($0)) }, window: true,
                          id: "batch") { [weak self] option in try self?.answerBatchWindow(option) }
    }

    private func batchOptionTitle(_ option: BatchWindowOption) -> String {
        switch option {
        case .addInputs: String(localized: "Add…")
        case .savePreset: String(localized: "Save Preset")
        case .run: String(localized: "Run")
        case .cancel: String(localized: "Cancel Batch")
        case .close: String(localized: "Close")
        case .addStep(let action):
            String(format: String(localized: "Add step: %@"), BatchStepCatalog.entry(action)?.localizedTitle ?? action)
        case .loadPreset(let name): String(format: String(localized: "Load preset %@"), name)
        default: batchNumberedOptionTitle(option)
        }
    }

    private func batchNumberedOptionTitle(_ option: BatchWindowOption) -> String {
        switch option {
        case .removeStep(let number): String(format: String(localized: "Remove step %lld"), number)
        case .moveStep(let number, true): String(format: String(localized: "Move step %lld up"), number)
        case .moveStep(let number, false): String(format: String(localized: "Move step %lld down"), number)
        case .openItem(let number): String(format: String(localized: "Open item %lld"), number)
        case .revealItem(let number): String(format: String(localized: "Reveal item %lld"), number)
        default: option.id
        }
    }

    /// Answers after the request, from the run loop like a click: Add… opens a file panel (`ui respond --path`
    /// answers it), and Run or Open may ask about unsaved changes in an alert. Step edits apply at once, so the next
    /// `ui dialog` lists them.
    private func answerBatchWindow(_ id: String) throws {
        guard let option = BatchWindowOption(id), try !editBatchPipeline(option) else { return }
        let model = batchWindow
        RunLoop.main.perform(inModes: [.default]) {
            MainActor.assumeIsolated {
                switch option {
                case .addInputs: model.chooseInputs()
                case .savePreset: model.savePreset()
                case .run: model.start()
                case .cancel: model.cancel()
                case .close: model.close()
                case .openItem(let number): model.openItem(number - 1)
                case .revealItem(let number): model.revealItem(number - 1)
                default: break
                }
            }
        }
    }

    /// Applies a step or preset option to the pipeline; false for the other options.
    private func editBatchPipeline(_ option: BatchWindowOption) throws -> Bool {
        let model = batchWindow
        switch option {
        case .addStep(let action):
            guard let entry = BatchStepCatalog.entry(action) else { throw ModalError("No batch step \(action)") }
            model.addStep(action, label: entry.localizedTitle)
        case .removeStep(let number): model.removeStep(number - 1)
        case .moveStep(let number, let up): model.moveStep(number - 1, by: up ? -1 : 1)
        case .loadPreset(let name): model.loadPreset(try batchPresets.load(name))
        default: return false
        }
        return true
    }

    /// The window's state in one paragraph for `ui dialog`.
    private func batchWindowSummary() -> String {
        let model = batchWindow
        let pipeline = model.pipeline
        var lines = [
            "Pipeline \(pipeline.name ?? "(unnamed)"): \(pipeline.inputs.count) inputs, \(model.items.count) items"
                + (model.itemsError.map { " (\($0))" } ?? ""),
            "Steps: " + (pipeline.steps.isEmpty ? "none" : pipeline.steps.enumerated()
                .map { "\($0 + 1). \(model.title($1)) [\($1.action)]" }.joined(separator: " · ")),
        ]
        if let selected = model.selectedStep { lines.append("Selected step: \(selected + 1)") }
        if !model.message.isEmpty { lines.append("Message: " + model.message) }
        if let run = model.run {
            lines.append("Queue \(run.id) \(run.state.rawValue): " + run.items.map { item in
                let status = BatchQueueStatus(item: item, jobs: jobs)
                return "\(item.source.name) \(item.state.rawValue) – \(status.result)"
            }.joined(separator: "; "))
        }
        return lines.joined(separator: "\n")
    }
}
