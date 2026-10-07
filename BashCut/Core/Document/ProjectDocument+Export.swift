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

    func startExport(
        name: String, preset: ExportPreset, directory: URL, includeSubRip: Bool,
        normalizeAudio: Bool = false
    ) {
        do {
            try startExportAuthorized(
                name: name, preset: preset, directory: directory, includeSubRip: includeSubRip,
                normalizeAudio: normalizeAudio)
        } catch {
            message = error.localizedDescription
        }
    }

    /// Validates and queues an export of the project as it is now; returns the job ID.
    @discardableResult
    func startExportAuthorized(
        name: String, preset: ExportPreset, directory: URL, includeSubRip: Bool,
        normalizeAudio: Bool = false, author: Author = .user, videoBitRate: Int? = nil
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
            project: project, root: root, workspace: settings.workspace, name: name, preset: preset,
            directory: directory, includeSubRip: includeSubRip, normalizeAudio: normalizeAudio,
            reserved: exports.queue.reservedOutputs)
        request.videoBitRate = videoBitRate
        let queued = exports.isRunning
        let session = sessionID
        let name = request.output.lastPathComponent
        let job = try exports.enqueue(request, author: author) { [weak self] result in
            guard let self, session == sessionID else { return }
            if !exports.isRunning { ui.showExportProgress = false }
            switch result {
            case .success(let outcome):
                finishExport(request, outcome: outcome)
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

    private func finishExport(_ request: ExportRequest, outcome: ExportOutcome) {
        let current = project.revision == request.source.revision
        if current, let audio = ExportController.normalizedAudio(outcome, current: project["audio"]) {
            apply(.setProjectProperties(patch: ["audio": audio]), label: "Normalize audio")
        }
        // The write-back above only stores the gain the export already applied, so the measurement describes it.
        recordReviewLoudness(
            outcome.finalMeasurement, revision: current ? project.revision : request.source.revision, preset: request.preset)
        lastRender = (outcome.receipt.url, current ? project.revision : request.source.revision)
        measureDelivered(request, url: outcome.receipt.url, revision: current ? project.revision : request.source.revision)
        DebugLog.write("export", "done \(outcome.receipt.url.path)")
        emitPluginEvent(.exportFinished, [
            "output": .string(outcome.receipt.url.path), "preset": .string(request.preset.rawValue),
            "rev": .integer(request.source.revision),
        ])
        message = String(localized: "Export complete")
        // Keep the report for later when more exports are waiting.
        if !exports.isRunning { ui.showExportReport = true }
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
                DebugLog.write("export", "qc \(preset): drift \(facts.drift ?? 0) black \(facts.black.count) silence \(facts.silence.count)")
            } catch {
                DebugLog.write("export", "qc failed: \(error.localizedDescription)")
            }
        }
    }
}
