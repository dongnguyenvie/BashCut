import BashCutAutomation
import BashCutProject
import Foundation
import Observation

/// What the batch runner needs from the editor: its one open project, the command handlers the CLI reaches and the
/// job center. The document implements it; tests implement it over a registry of their own.
@MainActor public protocol BatchHost: AnyObject {
    var jobs: JobCenter { get }
    /// The project file open now, nil when none.
    var openProjectFile: URL? { get }
    /// The open project's revision, for steps whose command takes `baseRev`.
    var projectRevision: Int? { get }
    /// The open project's first media ID, for `{media}` before any step returned one.
    var firstMediaID: String? { get }
    /// Where projects made for file inputs go when the pipeline names no folder.
    var defaultProjectsFolder: URL { get }
    /// Runs a catalogued command exactly as a CLI request: spec validation, then its handler, as the batch's author.
    func invoke(_ method: String, _ params: [String: JSONValue]) async throws -> JSONValue
    /// Whether `id` is an installed plugin action (`plugins actions`).
    func isPluginAction(_ id: String) -> Bool
    /// Queues one export of the open project for an approved batch: its job and the file it writes.
    func startBatchExport(preset: String, name: String, options: [String: JSONValue]) throws -> (job: String, file: URL)
    /// The run ended (completed, failed or cancelled).
    func runFinished(_ run: BatchRunStatus)
}

/// Runs batch pipelines (P2-C1): each item becomes a project (decision D4), opened in the editor, and every step runs
/// through the command handlers the CLI uses, as a job in the job center. Items run one at a time, because each step
/// acts on the one open project. The runs survive project switches (which drop the job list); `batch status` reads
/// them from here and the batch window (P2-C2) observes `runs`.
@MainActor @Observable
public final class BatchRunner {
    /// The step action that exports the item: each preset of `params.presets` (else the template's outputs), named by
    /// `outputName`. It is covered by the approval of the batch run itself, as `export.start` cannot be a step.
    public static let exportAction = "export"
    /// Commands a step may not run even when they need no approval: they open or close projects (the runner does
    /// that) or start batches.
    public static let refusedActions: Set<String> = [
        "project.open", "project.create", "project.close", "project.folder", "edl.import",
    ]
    public static let historyLimit = 10

    public private(set) var runs: [BatchRunStatus] = []
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    /// The job the active step waits on, so cancelling the batch cancels it too.
    @ObservationIgnored private var activeJob: String?
    /// The approval prompt each run waits on, so a refused prompt marks its run denied.
    @ObservationIgnored public var approvals: [String: UUID] = [:]

    public init() {}

    public var active: BatchRunStatus? { runs.last { !$0.state.isFinished } }
    public func run(_ id: String) -> BatchRunStatus? { runs.last { $0.id == id } }

    // MARK: Checking

    /// Throws for a step a batch may not run: `approval` commands (exports go through the `export` step), project
    /// switches, batch commands, and IDs that are neither a command nor an installed plugin action.
    public static func check(_ pipeline: BatchPipeline, isPluginAction: (String) -> Bool) throws {
        try pipeline.validate()
        if let unknown = pipeline.template.outputs.first(where: { !OutputPresetName.all.contains($0) }) {
            throw RPCFailure(-32602, BatchMessages.text(BatchMessages.unknownOutput, unknown, OutputPresetName.all.joined(separator: ", ")))
        }
        for (index, step) in pipeline.steps.enumerated() {
            if step.action == exportAction {
                let presets = presets(step, pipeline)
                if presets.isEmpty { throw RPCFailure(-32602, BatchMessages.step(BatchMessages.exportNeedsPresets, index, step.action)) }
                if let unknown = presets.first(where: { !OutputPresetName.all.contains($0) }) {
                    throw RPCFailure(-32602, BatchMessages.step(BatchMessages.exportUnknownPreset, index, step.action, unknown))
                }
                continue
            }
            guard let spec = CommandCatalog.spec(named: step.action) else {
                guard isPluginAction(step.action) else {
                    throw RPCFailure(-32602, BatchMessages.step(BatchMessages.unknownAction, index, step.action))
                }
                continue
            }
            if let refusal = stepRefusal(spec) { throw RPCFailure(-32602, BatchMessages.step(refusal, index, step.action)) }
        }
    }

    /// The presets the export step exports: `params.presets` (a list or comma-separated), else the template outputs.
    public static func presets(_ step: BatchStep, _ pipeline: BatchPipeline) -> [String] {
        switch step.params["presets"] {
        case .array(let list)?: return list.compactMap(\.string)
        case .string(let list)?:
            return list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        default: return pipeline.template.outputs
        }
    }

    // MARK: Running

    /// Adds a run of `items`, waiting for approval or ready to start, and returns its ID.
    public func add(_ pipeline: BatchPipeline, items: [BatchItemSource], awaitingApproval: Bool) -> String {
        let id = "batch-" + UUID().uuidString.prefix(8).lowercased()
        runs.append(BatchRunStatus(id: id, pipeline: pipeline, items: items,
                                   state: awaitingApproval ? .awaitingApproval : .waiting))
        let finished = runs.filter(\.state.isFinished)
        if finished.count > Self.historyLimit {
            let dropped = Set(finished.prefix(finished.count - Self.historyLimit).map(\.id))
            runs.removeAll { dropped.contains($0.id) }
        }
        return id
    }

    /// Starts run `id`. `leave` is how the first item leaves the project open before it (`saveCurrent` or
    /// `discardCurrent`); later items save the batch's own projects.
    public func start(_ id: String, host: any BatchHost, author: Author, leave: [String: JSONValue] = [:]) {
        guard let index = runs.firstIndex(where: { $0.id == id }), !runs[index].state.isFinished,
            runs[index].state != .running
        else { return }
        runs[index].state = .running
        approvals[id] = nil
        tasks[id] = Task { [weak self] in
            await self?.execute(id, host: host, author: author, leave: leave)
            self?.tasks[id] = nil
            if let run = self?.run(id) { host.runFinished(run) }
        }
    }

    /// Drops a run that never started (its approval could not be queued).
    public func forget(_ id: String) {
        guard run(id)?.state == .awaitingApproval || run(id)?.state == .waiting else { return }
        runs.removeAll { $0.id == id }
        approvals[id] = nil
    }

    /// The user refused the batch's approval.
    public func deny(_ id: String) {
        update(id) { run in
            guard run.state == .awaitingApproval else { return }
            run.state = .denied
            run.finishedAt = Date()
            for index in run.items.indices { run.items[index].state = .skipped }
        }
        approvals[id] = nil
    }

    /// Cancels a waiting or running batch and its running step's job; false when it is unknown or finished.
    @discardableResult
    public func cancel(_ id: String, jobs: JobCenter? = nil) -> Bool {
        guard let run = run(id), !run.state.isFinished else { return false }
        if let task = tasks[id] {
            task.cancel()
            if let activeJob { jobs?.cancel(activeJob) }
        } else {
            update(id) { run in
                run.state = .cancelled
                run.finishedAt = Date()
                for index in run.items.indices where !run.items[index].state.isFinished { run.items[index].state = .cancelled }
            }
        }
        return true
    }

    /// Waits until run `id` changes state, an item changes state or step, or it finishes, up to `duration`.
    public func wait(_ id: String, for duration: Duration) async throws -> (run: BatchRunStatus, changed: Bool)? {
        guard let start = run(id) else { return nil }
        func mark(_ run: BatchRunStatus) -> [String] {
            [run.state.rawValue] + run.items.map { "\($0.state.rawValue)/\($0.currentStep ?? -1)" }
        }
        let deadline = ContinuousClock.now + duration
        var current = start
        while !current.state.isFinished, mark(current) == mark(start), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(150))
            guard let next = run(id) else { return nil }
            current = next
        }
        return (current, mark(current) != mark(start))
    }

    private func update(_ id: String, _ change: (inout BatchRunStatus) -> Void) {
        guard let index = runs.firstIndex(where: { $0.id == id }) else { return }
        change(&runs[index])
    }

    private func updateItem(_ id: String, _ item: Int, _ change: (inout BatchItemStatus) -> Void) {
        update(id) { change(&$0.items[item]) }
    }

    /// What every step of a run needs.
    struct Context {
        let id: String
        let pipeline: BatchPipeline
        let host: any BatchHost
        let author: Author
    }

    private func execute(_ id: String, host: any BatchHost, author: Author, leave: [String: JSONValue]) async {
        guard let pipeline = run(id)?.pipeline, let count = run(id)?.items.count else { return }
        let context = Context(id: id, pipeline: pipeline, host: host, author: author)
        var stopped = false
        for item in 0..<count {
            if Task.isCancelled { break }
            let succeeded = await runItem(item, in: context, leave: item == 0 ? leave : ["saveCurrent": .bool(true)])
            if !succeeded, !Task.isCancelled, pipeline.onFailure == .stop {
                stopped = true
                break
            }
        }
        let cancelled = Task.isCancelled
        update(id) { run in
            for index in run.items.indices where !run.items[index].state.isFinished {
                run.items[index].state = cancelled ? .cancelled : .skipped
            }
            run.state = cancelled ? .cancelled : stopped ? .failed : .completed
            if stopped { run.error = BatchMessages.stoppedAfterFailure }
            run.finishedAt = Date()
        }
    }

    /// Opens the item's project, runs every step and saves it; false when a step (or opening) failed.
    private func runItem(_ item: Int, in context: Context, leave: [String: JSONValue]) async -> Bool {
        let (id, pipeline, host) = (context.id, context.pipeline, context.host)
        guard let source = run(id)?.items[item].source else { return false }
        updateItem(id, item) { $0.state = .running }
        let project: URL
        do {
            project = try await open(source, pipeline: pipeline, host: host, leave: leave)
            updateItem(id, item) { $0.project = project }
        } catch {
            updateItem(id, item) { status in
                status.state = Task.isCancelled ? .cancelled : .failed
                status.error = BatchMessages.text(BatchMessages.openFailed, error.localizedDescription)
                for step in status.steps.indices { status.steps[step].state = .skipped }
            }
            return false
        }
        var variables = ["input": source.url.path, "name": source.name, "project": project.path]
        var failed = false
        for (index, step) in pipeline.steps.enumerated() {
            if failed || Task.isCancelled {
                updateItem(id, item) { $0.steps[index].state = Task.isCancelled ? .cancelled : .skipped }
                continue
            }
            updateItem(id, item) { status in
                status.currentStep = index
                status.steps[index].state = .running
            }
            variables["media"] = variables["media"] ?? host.firstMediaID
            do {
                guard host.openProjectFile?.standardizedFileURL == project.standardizedFileURL else {
                    throw RPCFailure(-32000, BatchMessages.projectChanged)
                }
                let outcome = try await perform(step, at: index, item: item, variables: variables, in: context)
                if let media = Self.mediaID(in: outcome.result) { variables["media"] = media }
                updateItem(id, item) { status in
                    status.steps[index].state = .completed
                    status.steps[index].result = Self.trimmed(outcome.result)
                    status.steps[index].outputs = outcome.outputs
                }
            } catch {
                failed = true
                let failure = RPCFailure.from(error)
                updateItem(id, item) { status in
                    status.steps[index].state = Task.isCancelled || JobCenter.isCancellation(error) ? .cancelled : .failed
                    status.steps[index].error = failure.message
                    status.steps[index].errorCategory = (error as? StepJobFailure)?.category ?? failure.category.rawValue
                    status.error = BatchMessages.step(BatchMessages.stepFailed, index, step.action, failure.message)
                }
            }
        }
        // Kept even after a failed step, so the item can be opened to fix where it stopped.
        _ = try? await host.invoke("project.save", [:])
        let cancelled = Task.isCancelled
        updateItem(id, item) { status in
            status.currentStep = nil
            status.state = cancelled ? .cancelled : failed ? .failed : .completed
        }
        return !failed && !cancelled
    }

    /// Creates the project of a file item from the template (a free folder name in the projects folder, the file's
    /// folder linked as footage), or opens a project item.
    private func open(
        _ source: BatchItemSource, pipeline: BatchPipeline, host: any BatchHost, leave: [String: JSONValue]
    ) async throws -> URL {
        switch source.kind {
        case .project:
            _ = try await host.invoke("project.open", leave.merging(["path": .string(source.url.path)]) { $1 })
        case .file:
            let parent = pipeline.projectsFolder.map {
                URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true).standardizedFileURL
            } ?? host.defaultProjectsFolder
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            var params = pipeline.template.createParameters.merging(leave) { $1 }
            params["name"] = .string(Self.freeProjectName(source.name, in: parent))
            params["directory"] = .string(parent.path)
            params["footage"] = .string(source.url.path)
            _ = try await host.invoke("project.create", params)
            if !pipeline.template.outputs.isEmpty {
                _ = try await host.invoke("project.format", [
                    "outputs": .string(pipeline.template.outputs.joined(separator: ",")),
                    "baseRev": .integer(host.projectRevision ?? 0),
                ])
            }
        }
        guard let file = host.openProjectFile else { throw RPCFailure(-32000, BatchMessages.noProjectOpened) }
        return file
    }

    /// `name`, or `name 2`, `name 3`… when a project folder of that name is already in `parent`.
    static func freeProjectName(_ name: String, in parent: URL) -> String {
        var candidate = name
        var number = 1
        while FileManager.default.fileExists(atPath: parent.appendingPathComponent(folderName(candidate)).path) {
            number += 1
            candidate = "\(name) \(number)"
        }
        return candidate
    }

    private static func folderName(_ name: String) -> String {
        var setup = ProjectSetup()
        setup.name = name
        return setup.folderName
    }
}

/// A step's job ended without completing: its error and category as the job reported them.
struct StepJobFailure: Error, LocalizedError, RPCFailureProviding {
    let message: String
    let category: String?
    var errorDescription: String? { message }
    var rpcFailure: RPCFailure { RPCFailure(-32000, message) }
}

extension BatchRunner {
    struct StepOutcome {
        var result: JSONValue
        var outputs: [String] = []
    }

    /// Runs one step: the export step, a command (an immediate one wrapped in a `batch.step` job; a job command waited
    /// on) or a plugin action through `plugins.run`.
    func perform(
        _ step: BatchStep, at index: Int, item: Int, variables: [String: String], in context: Context
    ) async throws -> StepOutcome {
        let (id, pipeline, host, author) = (context.id, context.pipeline, context.host, context.author)
        let params = step.resolvedParams(variables)
        if step.action == Self.exportAction {
            var outputs: [String] = []
            var results: [JSONValue] = []
            let options = params.filter { $0.key != "presets" }
            for preset in Self.presets(step, pipeline) {
                let name = pipeline.outputFileName(item: variables["name"] ?? "item", index: item, preset: preset)
                let started = try host.startBatchExport(preset: preset, name: name, options: options)
                updateItem(id, item) { $0.steps[index].job = started.job }
                let job = try await finished(started.job, host: host)
                outputs.append(job.result.object["path"]?.string ?? started.file.path)
                results.append(.object(["preset": .string(preset), "job": .string(started.job)]))
            }
            return StepOutcome(result: .object(["exports": .array(results)]), outputs: outputs)
        }
        guard let spec = CommandCatalog.spec(named: step.action) else {
            let started = try await host.invoke("plugins.run", ["action": .string(step.action), "params": .object(params)])
            return try await outcome(of: started, id: id, item: item, step: index, host: host)
        }
        var values = params
        if spec.parameters.contains(where: { $0.name == "baseRev" }), values["baseRev"] == nil {
            values["baseRev"] = .integer(host.projectRevision ?? 0)
        }
        if spec.execution == .job {
            return try await outcome(of: try await host.invoke(step.action, values), id: id, item: item, step: index, host: host)
        }
        let job = host.jobs.start("batch.step", author: author, detail: step.label ?? step.action) { [values] _ in
            try await host.invoke(step.action, values)
        }
        updateItem(id, item) { $0.steps[index].job = job }
        return StepOutcome(result: try await finished(job, host: host).result)
    }

    /// A command's result; when it started a job, that job's result once it finishes.
    private func outcome(of result: JSONValue, id: String, item: Int, step: Int, host: any BatchHost) async throws
        -> StepOutcome
    {
        guard let job = result.object["job"]?.string else { return StepOutcome(result: result) }
        updateItem(id, item) { $0.steps[step].job = job }
        return StepOutcome(result: try await finished(job, host: host).result)
    }

    /// Waits for job `id` to finish, cancelling it when the batch is cancelled; throws unless it completed.
    private func finished(_ id: String, host: any BatchHost) async throws -> Job {
        activeJob = id
        defer { activeJob = nil }
        while true {
            guard let job = host.jobs.job(id) else { throw StepJobFailure(message: BatchMessages.text(BatchMessages.jobDropped, id), category: nil) }
            if !job.isActive {
                guard job.state == .completed else {
                    if job.state == .cancelled { throw CancellationError() }
                    throw StepJobFailure(message: job.error ?? BatchMessages.jobFailed, category: job.errorCategory)
                }
                return job
            }
            do {
                // Returns on any state or step change; the loop above decides whether the job is done.
                _ = try await host.jobs.wait(id, for: .seconds(60))
            } catch {
                host.jobs.cancel(id)
                throw error
            }
        }
    }

    /// The media a step result names (`media import` gives `media`), for `{media}` in later steps.
    static func mediaID(in result: JSONValue) -> String? {
        if let media = result.object["media"]?.string { return media }
        return result.object["files"]?.array.first?.object["media"]?.string
    }

    /// A step result for `batch status`: large lists and nested `changes` digests left out.
    static func trimmed(_ result: JSONValue) -> JSONValue {
        guard case .object(var fields) = result else { return result }
        fields["changes"] = nil
        for (key, value) in fields {
            if case .array(let list) = value, list.count > 20 { fields[key] = .integer(list.count) }
        }
        return .object(fields)
    }
}
