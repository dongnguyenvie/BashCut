import BashCutDocument
import BashCutProject
import Foundation

/// The batch runner window (P2-C2): File ▸ Batch…, `ui action open batch`, and a tool card's "Run on › Many projects /
/// files…", which opens it with that tool as the first step. Agents read and drive it as the `batch` window dialog.
extension ProjectDocument {
    func openBatch(_ firstStep: BatchStep? = nil) {
        batchWindow.open(firstStep: firstStep)
    }

    /// The window as a dialog (`ui dialog`, `ui respond --dialog sheet:batch`): the pipeline in the message, and Add
    /// inputs, Save preset, Run, Cancel, and Open/Reveal for each finished item of the queue.
    func batchWindowSheet() -> ModalSheet? {
        let model = batchWindow
        guard model.isOpen else { return nil }
        var options = [
            ModalOption("add-inputs", String(localized: "Add…")), ModalOption("save-preset", String(localized: "Save Preset")),
        ]
        options.append(model.running ? ModalOption("cancel", String(localized: "Cancel Batch"))
                                     : ModalOption("run", String(localized: "Run")))
        let finished = model.run?.items.enumerated().filter { $0.element.project != nil && $0.element.state.isFinished } ?? []
        if !model.running {
            for (index, _) in finished {
                options.append(ModalOption("open-\(index + 1)", String(format: String(localized: "Open item %lld"), index + 1)))
                options.append(ModalOption("reveal-\(index + 1)", String(format: String(localized: "Reveal item %lld"), index + 1)))
            }
        }
        options.append(ModalOption("close", String(localized: "Close")))
        return ModalSheet(name: "batch", title: "Batch", message: batchWindowSummary(), options: options, window: true,
                          id: "batch") { [weak self] option in self?.answerBatchWindow(option) }
    }

    /// Answers after the request, from the run loop like a click: Add… opens a file panel (`ui respond --path`
    /// answers it), and Run or Open may ask about unsaved changes in an alert.
    private func answerBatchWindow(_ option: String) {
        let model = batchWindow
        RunLoop.main.perform(inModes: [.default]) {
            MainActor.assumeIsolated {
                switch option {
                case "add-inputs": model.chooseInputs()
                case "save-preset": model.savePreset()
                case "run": model.start()
                case "cancel": model.cancel()
                case "close": model.close()
                default:
                    let parts = option.split(separator: "-")
                    guard parts.count == 2, let number = Int(parts[1]) else { return }
                    if parts[0] == "open" { model.openItem(number - 1) } else { model.revealItem(number - 1) }
                }
            }
        }
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
