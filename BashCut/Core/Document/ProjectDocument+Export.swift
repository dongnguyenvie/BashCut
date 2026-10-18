import AppKit
import BashCutAutomation
import BashCutDocument
import BashCutEngine
import BashCutInterchange
import BashCutProject
import Foundation

extension ProjectDocument {
    func exportOTIO() {
        guard fileURL != nil else {
            message = String(localized: "Save the project before exporting")
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "otio")].compactMap { $0 }
        panel.nameFieldStringValue = project.name + ".otio"
        panel.directoryURL = fileURL?.deletingLastPathComponent().appendingPathComponent("render")
        guard let url = ModalCenter.shared.save(panel, name: "export-otio") else { return }
        do {
            try TimelineFormats.write(project, with: OpenTimelineIOExporter(), to: url, allowReplace: true)
            message = String(localized: "OTIO exported")
        } catch { message = error.localizedDescription }
    }

    /// The Export sheet: one queued export per checked output (#593), named `name-<preset>` when there are several.
    func startExport(
        name: String, presets: [ExportPreset], directory: URL, includeSubRip: Bool,
        normalizeAudio: Bool = false, withoutRoles: Set<String> = [], runSteps: Bool = false
    ) {
        let export: @MainActor @Sendable () throws -> JSONValue = { [unowned self] in
            .array(try presets.map { preset in
                .string(try startExportAuthorized(
                    name: ExportRequest.outputName(name, preset: preset, among: presets), preset: preset,
                    directory: directory, includeSubRip: includeSubRip, normalizeAudio: normalizeAudio,
                    withoutRoles: withoutRoles))
            })
        }
        // Finalise and export (#634): the plugins' export steps first, then the exports.
        do {
            try runExport(after: runSteps ? exportSteps(for: presets) : [], name: name, author: .user, export)
        } catch {
            message = error.localizedDescription
        }
    }

    /// Validates and queues an export of the project as it is now; returns the job ID.
    @discardableResult
    func startExportAuthorized(
        name: String, preset: ExportPreset, directory: URL, includeSubRip: Bool,
        normalizeAudio: Bool = false, author: Author = .user, videoBitRate: Int? = nil, withoutRoles: Set<String> = []
    ) throws -> String {
        guard !preview.isMaintainingCache else { throw AutomationBusy() }
        guard let root = fileURL?.deletingLastPathComponent() else {
            throw ProjectError.invalid("Save the project before exporting")
        }
        try checkExportable()
        if normalizeAudio {
            plugins.refresh(projectRoot: root)
            guard !plugins.providers(for: "audio.loudness").isEmpty else {
                throw ProjectError.invalid("Install a plugin that provides audio.loudness")
            }
        }
        var request = try ExportRequest(
            project: withoutRoles.isEmpty ? project : project.muting(roles: withoutRoles), root: root,
            workspace: settings.workspace, name: name, preset: preset,
            directory: directory, includeSubRip: includeSubRip, normalizeAudio: normalizeAudio,
            reserved: exports.queue.reservedOutputs)
        request.videoBitRate = videoBitRate
        request.withoutRoles = withoutRoles
        request.transcripts = reviewTranscripts
        let queued = exports.isRunning
        let session = sessionID
        let name = request.output.lastPathComponent
        let job = try exports.enqueue(request, author: author) { [weak self] result in
            guard let self, session == sessionID else { return }
            if !exports.isRunning { ui.showExportProgress = false }
            switch result {
            case .success(let outcome):
                finishExport(request, outcome: outcome, author: author)
                logAutoStage("export", evidence: [
                    request.output.path, "\(preset.rawValue) export finished",
                    normalizeAudio ? "loudness measured and normalized" : "loudness not measured (no normalize-audio)",
                ], author: author)
                exports.post(ExportNotice(.finished, name: name, author: author))
            case .failure(let error) where JobCenter.isCancellation(error):
                message = String(localized: "Export cancelled")
                exports.post(ExportNotice(.cancelled, name: name, author: author))
            case .failure(let error):
                message = error.localizedDescription
                exports.post(ExportNotice(.failed(error.localizedDescription), name: name, author: author))
                emitPluginEvent(.exportFailed, [
                    "output": .string(request.output.path), "preset": .string(preset.rawValue),
                    "error": .string(error.localizedDescription),
                ])
            }
        }
        ui.showExport = false
        message = queued ? String(localized: "Export queued") : String(localized: "Preparing export…")
        exports.post(ExportNotice(queued ? .queued : .started, name: name, author: author))
        DebugLog.write("export", "queued \(job) \(preset.rawValue) → \(request.output.path)")
        emitPluginEvent(.exportStarted, [
            "job": .string(job), "output": .string(request.output.path), "preset": .string(preset.rawValue),
            "author": .string(author.rawValue),
        ])
        return job
    }

    /// Refuses an export of video this Mac cannot decode, or while issues `review.blockExport` names are open.
    private func checkExportable() throws {
        // The export build refuses these too; checking the preview's build here fails the request, not a later job.
        if let undecodable = preview.currentBuild?.undecodable, !undecodable.isEmpty {
            throw UndecodableMediaError(undecodable)
        }
        let blocking = TimelineReview.blockingExport(project, issues: reviewIssues())
        if !blocking.isEmpty {
            throw ProjectError.invalid("review.blockExport stops the export while these are open: "
                + blocking.map(\.id).joined(separator: ", "))
        }
    }

    private func finishExport(_ request: ExportRequest, outcome: ExportOutcome, author: Author) {
        let current = project.revision == request.source.revision
        guard request.withoutRoles.isEmpty else {
            // A version without some of the sound is not the edit's mix: its loudness and QC stay out of review.
            DebugLog.write("export", "done \(outcome.receipt.url.path) without \(request.withoutRoles.sorted().joined(separator: ","))")
            emitPluginEvent(.exportFinished, [
                "output": .string(outcome.receipt.url.path), "preset": .string(request.preset.rawValue),
                "rev": .integer(request.source.revision),
            ])
            message = String(localized: "Export complete")
            if !exports.isRunning, opensReport(author) { ui.showExportReport = true }
            return
        }
        // The export's loudness gain stays in the file it wrote: storing it in the project bumped the revision (the
        // agent's next edit failed as stale) and stacked under the next export's own measurement.
        recordReviewLoudness(
            outcome.finalMeasurement, revision: current ? project.revision : request.source.revision, preset: request.preset,
            measured: request.source)
        lastRender = (outcome.receipt.url, current ? project.revision : request.source.revision)
        measureDelivered(request, url: outcome.receipt.url, revision: current ? project.revision : request.source.revision)
        DebugLog.write("export", "done \(outcome.receipt.url.path)")
        emitPluginEvent(.exportFinished, [
            "output": .string(outcome.receipt.url.path), "preset": .string(request.preset.rawValue),
            "rev": .integer(request.source.revision),
        ])
        message = String(localized: "Export complete")
        // Keep the report for later when more exports are waiting.
        if !exports.isRunning, opensReport(author) { ui.showExportReport = true }
    }

    /// Only the user's own export opens the report sheet. An agent's export shows the toast (its Report button opens
    /// the sheet) or, during a run, the run panel's result card (#448): the sheet's open animation runs a nested run
    /// loop that holds the main actor and the agent's next call with it (#350).
    /// Not during a batch: each item's export would open the sheet again (the queue shows its files).
    private func opensReport(_ author: Author) -> Bool {
        guard author == .user, batches.active == nil else {
            runPanel.refresh()
            return false
        }
        return true
    }

    /// Measures the written file in the background (P1-E6); review reads it for the revision it shows.
    private func measureDelivered(_ request: ExportRequest, url: URL, revision: Int) {
        let preset = request.preset.argument
        let fps = request.project.fps.value
        let size = (request.project.width, request.project.height)
        Task { [weak self] in
            do {
                let facts = try await DeliveredQC.measure(url, revision: revision, preset: preset, expectedFps: fps, expectedSize: size)
                guard let self else { return }
                deliveredQC.removeAll { $0.preset == preset }
                deliveredQC.append(facts)
                // The result card counted the issues before this file was measured (black or silent stretches).
                runPanel.refresh(force: true)
                DebugLog.write("export", "qc \(preset): drift \(facts.drift ?? 0) black \(facts.black.count) silence \(facts.silence.count)")
            } catch {
                DebugLog.write("export", "qc failed: \(error.localizedDescription)")
            }
        }
    }
}
