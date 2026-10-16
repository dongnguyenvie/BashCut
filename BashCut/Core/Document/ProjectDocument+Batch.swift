import BashCutAutomation
import BashCutDocument
import BashCutEngine
import BashCutProject
import Foundation

/// Batch pipelines (P2-C1): `batch run` checks the pipeline, asks the user to approve the whole batch once and hands
/// it to the app-wide `BatchRunner`, which opens each item's project here and runs the steps through the same handlers
/// as the CLI.
extension ProjectDocument {
    var batches: BatchRunner { automation.batches }
    var batchPresets: BatchPresetStore { .user(applicationSupport: Self.libraryApplicationSupport) }

    func registerBatchCommands() {
        handleAuthored("batch.run") { document, arguments, author in
            try await document.startBatch(arguments, author: author)
        }
        handle("batch.status") { document, arguments, _ in
            try await document.batchStatus(arguments)
        }
        handleAuthored("batch.cancel") { document, arguments, _ in
            document.markDeniedBatches()
            guard let id = arguments.optionalString("batch") ?? document.batches.active?.id else {
                throw RPCFailure(-32602, "No batch is running")
            }
            if document.batches.run(id)?.state == .awaitingApproval,
                document.privilegedApproval?.id == document.batches.approvals[id]
            {
                document.resolvePrivilegedApproval(false)
            }
            let cancelled = document.batches.cancel(id, jobs: document.jobs)
            guard cancelled || document.batches.run(id) != nil else { throw RPCFailure(-32602, "No batch \(id)") }
            return .object(["batch": .string(id), "cancelled": .bool(cancelled)])
        }
        handleAuthored("batch.presets") { document, arguments, _ in
            try document.batchPresetsCommand(arguments)
        }
    }

    private func startBatch(_ arguments: CommandArguments, author: Author) async throws -> JSONValue {
        markDeniedBatches()
        if let active = batches.active {
            throw RPCFailure(-32003, "Batch \(active.id) is \(active.state.rawValue); wait for it or batch cancel it",
                             category: .busyRunning)
        }
        var pipeline = try batchPipeline(arguments)
        let base = arguments.optionalString("base").map { URL(fileURLWithPath: $0, isDirectory: true) }
        if base == nil, let relative = pipeline.inputs.first(where: { !$0.path.hasPrefix("/") && !$0.path.hasPrefix("~") }) {
            throw RPCFailure(-32602, "Input \(relative.path) is relative: give absolute paths or base")
        }
        if let projects = pipeline.projectsFolder, !projects.hasPrefix("/"), !projects.hasPrefix("~") {
            guard let base else { throw RPCFailure(-32602, "projectsFolder \(projects) is relative: give an absolute path or base") }
            pipeline.projectsFolder = base.appendingPathComponent(projects).standardizedFileURL.path
        }
        let items: [BatchItemSource]
        do {
            try BatchRunner.check(pipeline) { [plugins] in plugins.action($0) != nil }
            items = try pipeline.items(relativeTo: base)
        } catch let error as ProjectError { throw RPCFailure(-32602, error.localizedDescription) }
        let leave = try batchLeaveCurrent(arguments)
        let id = batches.add(pipeline, items: items, awaitingApproval: !settings.agentActionsAutoApproved)
        let approval: PrivilegedRequest
        do {
            approval = try queuePrivilegedApproval(
                method: "batch.run", author: author, arguments: Self.batchApprovalArguments(pipeline, items: items)
            ) { [weak self] in
                guard let self else { throw RPCFailure(-32000, "Editor closed") }
                batches.start(id, host: DocumentBatchHost(document: self, author: author), author: author, leave: leave)
            }
        } catch {
            batches.forget(id)
            throw error
        }
        if !approval.autoApproved {
            batches.approvals[id] = approval.id
            message = String(localized: "Waiting for approval: batch.run")
        }
        var result = batches.run(id)?.json(full: false).object ?? [:]
        result["approved"] = .bool(approval.autoApproved)
        return .object(result)
    }

    /// The pipeline from `pipeline` or a saved preset, with `inputs` replacing its inputs.
    private func batchPipeline(_ arguments: CommandArguments) throws -> BatchPipeline {
        let given = arguments["pipeline"]
        let preset = arguments.optionalString("preset")
        guard (given == nil) != (preset == nil) else { throw RPCFailure(-32602, "Give a pipeline or a preset") }
        do {
            var pipeline = try given.map(BatchPipeline.init(json:)) ?? batchPresets.load(preset ?? "")
            if let inputs = arguments.optionalString("inputs") {
                pipeline.inputs = inputs.split(separator: ",").map { BatchInput(path: $0.trimmingCharacters(in: .whitespaces)) }
                    .filter { !$0.path.isEmpty }
            }
            return pipeline
        } catch let error as ProjectError { throw RPCFailure(-32602, error.localizedDescription) }
    }

    /// The first item's way out of the open project, checked now so an unsaved project fails the request, not the batch.
    private func batchLeaveCurrent(_ arguments: CommandArguments) throws -> [String: JSONValue] {
        if arguments.bool("saveCurrent") { return ["saveCurrent": .bool(true)] }
        if arguments.bool("discardCurrent") { return ["discardCurrent": .bool(true)] }
        guard !dirty else {
            throw RPCFailure(
                -32602, "The open project has unsaved changes; pass saveCurrent or discardCurrent (CLI --save-current "
                    + "or --discard-current)")
        }
        return [:]
    }

    static func batchApprovalArguments(_ pipeline: BatchPipeline, items: [BatchItemSource]) -> [String: String] {
        let files = items.filter { $0.kind == .file }.count
        let steps = pipeline.steps.enumerated().map { "\($0 + 1). \($1.label ?? $1.action)" }.joined(separator: " · ")
        var arguments = [
            "items": "\(items.count): \(files) new from files, \(items.count - files) existing projects",
            "steps": steps, "on failure": pipeline.onFailure == .stop ? "stop the batch" : "skip the item",
            "output name": pipeline.outputName,
        ]
        if let name = pipeline.name { arguments["pipeline"] = name }
        if files > 0 { arguments["new projects in"] = pipeline.projectsFolder ?? "the projects folder" }
        let exports = pipeline.steps.filter { $0.action == BatchRunner.exportAction }
            .flatMap { BatchRunner.presets($0, pipeline) }
        if !exports.isEmpty { arguments["exports per item"] = exports.joined(separator: ", ") }
        return arguments
    }

    /// A run whose approval prompt is gone without starting was refused.
    func markDeniedBatches() {
        for (id, approval) in batches.approvals where privilegedApproval?.id != approval {
            batches.deny(id)
        }
    }

    private func batchStatus(_ arguments: CommandArguments) async throws -> JSONValue {
        markDeniedBatches()
        if arguments.bool("all"), arguments.optionalString("batch") == nil {
            return .object(["batches": .array(batches.runs.reversed().map { $0.json(full: false) })])
        }
        guard let id = arguments.optionalString("batch") ?? batches.runs.last?.id else {
            throw RPCFailure(-32602, "No batch has run in this session")
        }
        guard batches.run(id) != nil else { throw RPCFailure(-32602, "No batch \(id)") }
        guard let seconds = arguments.optionalInt("wait"), seconds > 0 else {
            return batches.run(id)?.json() ?? .null
        }
        guard let waited = try await batches.wait(id, for: .seconds(seconds)) else { return .null }
        var result = waited.run.json().object
        result["changed"] = .bool(waited.changed)
        result["timedOut"] = .bool(!waited.changed && !waited.run.state.isFinished)
        return .object(result)
    }

    private func batchPresetsCommand(_ arguments: CommandArguments) throws -> JSONValue {
        let store = batchPresets
        do {
            if let name = arguments.optionalString("remove") {
                return .object(["removed": .bool(try store.remove(name)), "name": .string(name)])
            }
            if let name = arguments.optionalString("get") { return try store.load(name).json }
            if let given = arguments["pipeline"] {
                var pipeline = try BatchPipeline(json: given)
                pipeline.name = arguments.optionalString("name") ?? pipeline.name
                if !arguments.bool("keepInputs") { pipeline.inputs = [] }
                try BatchRunner.check(Self.presetCheckCopy(pipeline)) { [plugins] in plugins.action($0) != nil }
                let url = try store.save(pipeline)
                return .object(["saved": .string(pipeline.name ?? ""), "path": .string(url.path)])
            }
        } catch let error as ProjectError { throw RPCFailure(-32602, error.localizedDescription) }
        return .object(["presets": .array(store.list().map { pipeline in
            .object([
                "name": pipeline.name.map(JSONValue.string) ?? .null,
                "steps": .array(pipeline.steps.map { .string($0.label ?? $0.action) }),
                "outputs": .array(pipeline.template.outputs.map(JSONValue.string)),
                "inputs": .integer(pipeline.inputs.count),
            ])
        }), "folder": .string(store.root.path)])
    }

    /// A preset may be saved without inputs; it is checked as if it had one.
    private static func presetCheckCopy(_ pipeline: BatchPipeline) -> BatchPipeline {
        var copy = pipeline
        if copy.inputs.isEmpty { copy.inputs = [BatchInput(path: "/")] }
        return copy
    }

    /// One export of the open project for an approved batch. The graphics-draft guard applies; the draft-audit
    /// guard does not, as the user approved the batch and each result is a project to open and fix (D4).
    func startBatchExport(preset name: String, fileName: String, options: [String: JSONValue], author: Author) throws
        -> (job: String, file: URL)
    {
        let preset = try Self.exportPreset(name)
        guard let root = fileURL?.deletingLastPathComponent() else { throw RPCFailure(-32602, "Save the project before exporting") }
        guard project.duration > 0 else { throw RPCFailure(-32602, "The timeline is empty") }
        if let failure = WorkflowChecklist.graphicsDraftGuard(project) { throw Self.guardFailure(failure) }
        let directory = root.appendingPathComponent("render", isDirectory: true)
        let includeSubRip = options["includeSRT"]?.bool ?? false
        let available = ExportRequest.availableName(
            fileName, preset: preset, directory: directory, includeSubRip: includeSubRip,
            reserved: exports.queue.reservedOutputs, ignoringFiles: false)
        let job = try startExportAuthorized(
            name: available, preset: preset, directory: directory, includeSubRip: includeSubRip,
            normalizeAudio: options["normalizeAudio"]?.bool ?? false, author: author,
            videoBitRate: options["bitrate"]?.double.map { Int($0 * 1_000_000) },
            withoutRoles: try Self.exportWithoutRoles(options["without"]?.string))
        return (job, directory.appendingPathComponent(available).appendingPathExtension(preset.fileExtension))
    }
}
