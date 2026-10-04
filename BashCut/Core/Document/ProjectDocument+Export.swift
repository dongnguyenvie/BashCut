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
        normalizeAudio: Bool = false, author: Author = .user
    ) throws -> String {
        guard !preview.isMaintainingCache else { throw AutomationBusy() }
        guard let root = fileURL?.deletingLastPathComponent() else {
            throw ProjectError.invalid("Save the project before exporting")
        }
        if normalizeAudio {
            plugins.refresh(projectRoot: root)
            guard !plugins.providers(for: "audio.loudness").isEmpty else {
                throw ProjectError.invalid("Install a plugin that provides audio.loudness")
            }
        }
        let request = try ExportRequest(
            project: project, root: root, workspace: settings.workspace, name: name, preset: preset,
            directory: directory, includeSubRip: includeSubRip, normalizeAudio: normalizeAudio,
            reserved: exports.queue.reservedOutputs)
        let queued = exports.isRunning
        let session = sessionID
        let job = try exports.enqueue(request, author: author) { [weak self] result in
            guard let self, session == sessionID else { return }
            switch result {
            case .success(let outcome): finishExport(request, outcome: outcome)
            case .failure(let error) where JobCenter.isCancellation(error):
                message = String(localized: "Export cancelled")
            case .failure(let error):
                message = error.localizedDescription
                emitPluginEvent(.exportFailed, [
                    "output": .string(request.output.path), "preset": .string(preset.rawValue),
                    "error": .string(error.localizedDescription),
                ])
            }
        }
        ui.showExport = false
        message = queued ? String(localized: "Export queued") : String(localized: "Preparing export…")
        DebugLog.write("export", "queued \(job) \(preset.rawValue) → \(request.output.path)")
        emitPluginEvent(.exportStarted, [
            "job": .string(job), "output": .string(request.output.path), "preset": .string(preset.rawValue),
            "author": .string(author.rawValue),
        ])
        return job
    }

    private func finishExport(_ request: ExportRequest, outcome: ExportOutcome) {
        if project.revision == request.source.revision,
            let audio = ExportController.normalizedAudio(outcome, current: project["audio"])
        {
            apply(.setProjectProperties(patch: ["audio": audio]), label: "Normalize audio")
        }
        DebugLog.write("export", "done \(outcome.receipt.url.path)")
        emitPluginEvent(.exportFinished, [
            "output": .string(outcome.receipt.url.path), "preset": .string(request.preset.rawValue),
            "rev": .integer(request.source.revision),
        ])
        message = String(localized: "Export complete")
        // Keep the report for later when more exports are waiting.
        if !exports.isRunning { ui.showExportReport = true }
    }
}
