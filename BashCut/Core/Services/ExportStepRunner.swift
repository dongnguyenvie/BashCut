import BashCutAutomation
import BashCutEngine
import BashCutPlugin
import BashCutProject
import Foundation

/// A plugin export step (plugin API 12, #634) a final export runs first: the plugin and its contribution.
public struct ExportStepRun: Sendable, Equatable {
    public let plugin: InstalledPlugin
    public let step: PluginExportStepContribution

    public init(plugin: InstalledPlugin, step: PluginExportStepContribution) {
        self.plugin = plugin
        self.step = step
    }

    public var title: String { step.title.text }

    /// The steps of `plugins` (the ready ones) whose `when` holds for `project`, by plugin id, each plugin's in
    /// declared order; none when every preset is quick-draft, which may use drafts.
    public static func matching(_ plugins: [InstalledPlugin], project: Project, presets: [ExportPreset]) -> [ExportStepRun] {
        guard presets.contains(where: { $0 != .quickDraft }) else { return [] }
        return plugins.sorted { $0.id < $1.id }.flatMap { plugin in
            plugin.manifest.exportSteps.filter { $0.matches(project) }.map { ExportStepRun(plugin: plugin, step: $0) }
        }
    }

    public func json(_ project: Project) -> JSONValue {
        .object([
            "plugin": .string(plugin.id), "id": .string(step.id), "title": .string(title),
            "command": .string(([step.command.executable] + step.command.arguments).joined(separator: " ")),
            "when": .string(step.when),
            "media": .array((step.condition?.matchingMedia(project) ?? []).map(JSONValue.string)),
        ])
    }
}

/// Runs plugin export steps one after another as one job (`export.steps`) with progress and cancel, then the
/// export. Each step runs the plugin's file with its environment plus what `session` gives it (the app's socket and
/// a token that edits as the plugin) and changes the project itself; afterwards the project is read again. A cancel,
/// a failing step or a step whose `when` still holds stops the job and nothing is exported.
@MainActor
public struct ExportStepRunner {
    public static let method = "export.steps"

    public let jobs: JobCenter
    /// The environment one step gets and what to do when it ends (revoke its token).
    public let session: @MainActor (ExportStepRun) -> (environment: [String: String], end: @MainActor () -> Void)
    /// The project as it is now; nil when it was closed or switched, which cancels the steps.
    public let project: @MainActor () -> Project?

    public init(
        jobs: JobCenter,
        session: @escaping @MainActor (ExportStepRun) -> (environment: [String: String], end: @MainActor () -> Void),
        project: @escaping @MainActor () -> Project?
    ) {
        self.jobs = jobs
        self.session = session
        self.project = project
    }

    /// Starts the job and returns its ID. Its result is `{steps, exports}` with what `export` returned.
    @discardableResult
    public func start(
        _ steps: [ExportStepRun], author: Author,
        then export: @escaping @MainActor @Sendable () throws -> JSONValue,
        finished: @escaping @MainActor (Result<JSONValue, any Error>) -> Void = { _ in }
    ) -> String {
        let runner = self
        let count = Double(steps.count)
        return jobs.start(Self.method, author: author, detail: steps.first?.title) { reporter in
            var done: [JSONValue] = []
            for (index, run) in steps.enumerated() {
                try Task.checkCancellation()
                guard let project = runner.project() else { throw CancellationError() }
                reporter.progress(Double(index) / count, detail: run.title)
                done.append(run.json(project))
                try await runner.run(run, reporter: reporter, range: Double(index) / count...Double(index + 1) / count)
            }
            try Task.checkCancellation()
            guard let project = runner.project() else { throw CancellationError() }
            if let left = steps.first(where: { $0.step.matches(project) }) {
                let media = left.step.condition?.matchingMedia(project) ?? []
                throw RPCFailure(-32000, String(
                    format: String(localized: "Export step %@ (%@) finished, but %d media still match %@: %@. Nothing was exported."),
                    left.title, left.plugin.manifest.displayName, media.count, left.step.when, media.joined(separator: ", ")))
            }
            return .object(["steps": .array(done), "exports": try export()])
        } finished: { result in
            finished(result)
        }
    }

    /// One step: `::progress` lines move the job within `range` and their text becomes its step.
    private func run(_ run: ExportStepRun, reporter: JobReporter, range: ClosedRange<Double>) async throws {
        let (environment, end) = session(run)
        defer { end() }
        let progress = reporter.progressHandler(range: range)
        let label = String(format: String(localized: "Export step %@ (%@)"), run.title, run.plugin.manifest.displayName)
        try await PluginCommandRunner.run(
            run.step.command, plugin: run.plugin, directory: run.plugin.directory, extraEnvironment: environment,
            label: label, timeout: run.step.timeout
        ) { output in
            guard case .progress(let value, let text) = output else { return }
            progress(value)
            if let text { Task { @MainActor in reporter.detail(text) } }
        }
    }
}
