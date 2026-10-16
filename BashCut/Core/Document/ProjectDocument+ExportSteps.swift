import BashCutAutomation
import BashCutDocument
import BashCutEngine
import BashCutPlugin
import BashCutPlugins
import BashCutProject
import Foundation

/// Plugin export steps (plugin API 12, #634): blocking steps a final export runs first (`ExportStepRunner`).
extension ProjectDocument {
    /// The ready plugins' export steps a final export of `presets` runs first; none when every preset is quick-draft.
    func exportSteps(for presets: [ExportPreset]) -> [ExportStepRun] {
        guard presets.contains(where: { $0 != .quickDraft }) else { return [] }
        plugins.refresh(projectRoot: fileURL?.deletingLastPathComponent())
        return matchingExportSteps(for: presets)
    }

    /// `exportSteps(for:)` from the plugins as last loaded, without refreshing them: safe while drawing a view.
    func matchingExportSteps(for presets: [ExportPreset]) -> [ExportStepRun] {
        ExportStepRun.matching(plugins.plugins.filter(plugins.isReady), project: project, presets: presets)
    }

    /// Runs `export` at once, or after `steps` as one job (`startExportSteps`); returns the steps' job, if any.
    @discardableResult
    func runExport(
        after steps: [ExportStepRun], name: String, author: Author,
        _ export: @escaping @MainActor @Sendable () throws -> JSONValue
    ) throws -> String? {
        guard !steps.isEmpty else {
            _ = try export()
            return nil
        }
        return startExportSteps(steps, name: name, author: author, then: export)
    }

    /// Runs `steps` as one job with progress and cancel, then `export` on the project the steps left. The export
    /// counts as running meanwhile (toolbar, progress popover, `export status`); Cancel Export cancels the steps and
    /// nothing is exported. Returns the job ID.
    @discardableResult
    func startExportSteps(
        _ steps: [ExportStepRun], name: String, author: Author,
        then export: @escaping @MainActor @Sendable () throws -> JSONValue
    ) -> String {
        let session = sessionID
        let runner = ExportStepRunner(jobs: jobs, session: { [weak self] run in
            guard let self else { return ([:], {}) }
            // The step edits through the CLI as the plugin; its token dies with the step.
            let token = registry.issueToken(author: .plugin)
            var environment = AutomationPaths.sessionEnvironment(token: token, project: fileURL)
            environment["BASHCUT_EXPORT_STEP"] = run.step.id
            if let cli = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("bashcut"),
                FileManager.default.isExecutableFile(atPath: cli.path)
            {
                environment["BASHCUT_CLI"] = cli.path
            }
            return (environment, { [weak self] in self?.registry.revoke(token) })
        }, project: { [weak self] in
            guard let self, session == sessionID else { return nil }
            return project
        })
        let job = runner.start(steps, author: author, then: { [weak self] in
            self?.exports.endPreparing()
            return try export()
        }, finished: { [weak self] result in
            guard let self, session == sessionID else { return }
            exports.endPreparing()
            if !exports.isRunning { ui.showExportProgress = false }
            switch result {
            case .success: break
            case .failure(let error) where JobCenter.isCancellation(error):
                message = String(localized: "Export cancelled")
                exports.post(ExportNotice(.cancelled, name: name, author: author))
            case .failure(let error):
                message = error.localizedDescription
                exports.post(ExportNotice(.failed(error.localizedDescription), name: name, author: author))
            }
        })
        exports.beginPreparing(job: job, name: name, steps: steps.map(\.title))
        ui.showExport = false
        message = String(format: String(localized: "Before exporting: %@…"), steps.map(\.title).joined(separator: ", "))
        exports.post(ExportNotice(.started, name: name, author: author))
        DebugLog.write("export", "export steps \(job): \(steps.map { "\($0.plugin.id)/\($0.step.id)" }.joined(separator: ", "))")
        return job
    }
}
