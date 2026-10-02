import AppKit
import BashCutAutomation
import BashCutDocument
import BashCutEngine
import BashCutInterchange
import BashCutPlugin
import BashCutPlugins
import BashCutProject
import BashCutStorage
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
            try writeOTIO(to: url, allowReplace: true)
            message = String(localized: "OTIO exported")
        } catch { message = error.localizedDescription }
    }

    func writeOTIO(to url: URL, allowReplace: Bool = false) throws {
        guard allowReplace || !FileManager.default.fileExists(atPath: url.path) else {
            throw ProjectError.invalid("Choose a new export name; an output already exists")
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try OpenTimelineIOExporter.data(for: project).write(to: url, options: .atomic)
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
            project: project, root: root, workspace: agents.workspace, name: name, preset: preset,
            directory: directory, includeSubRip: includeSubRip, normalizeAudio: normalizeAudio,
            reserved: exports.reservedOutputs)
        let queued = exports.isRunning
        let session = sessionID
        let job = try exports.enqueue(request, author: author) { [weak self] result in
            guard let self, session == sessionID else { return }
            switch result {
            case .success(let outcome): finishExport(request, outcome: outcome)
            case .failure(let error) where JobCenter.isCancellation(error):
                message = String(localized: "Export cancelled")
            case .failure(let error): message = error.localizedDescription
            }
        }
        ui.showExport = false
        message = queued ? String(localized: "Export queued") : String(localized: "Preparing export…")
        DebugLog.write("export", "queued \(job) \(preset.rawValue) → \(request.output.path)")
        return job
    }

    /// Cancels the running export; queued exports start next.
    func cancelExport() { exports.cancelActive() }

    private func finishExport(_ request: ExportRequest, outcome: ExportOutcome) {
        let loudness = outcome.finalMeasurement
        if let generated = outcome.generated, let mixGain = outcome.mixGainDb,
            project.revision == request.source.revision
        {
            var audio = project["audio"]?.object ?? [:]
            audio["mixGainDb"] = .number(mixGain)
            if let loudness {
                audio["measuredLUFS"] = .number(loudness.integratedLUFS)
                audio["truePeakDbTP"] = .number(loudness.truePeakDbTP)
            }
            audio["measurementVerified"] = .bool(outcome.verified)
            if let range = loudness?.loudnessRangeLU { audio["loudnessRangeLU"] = .number(range) }
            audio["measuredBy"] = .object(generated.provenance.json)
            apply(.setProjectProperties(patch: ["audio": .object(audio)]), label: "Normalize audio")
        }
        let report = ExportReport(
            receipt: outcome.receipt, preset: request.preset,
            cutCount: request.source.tracks.first(where: { $0.role == "main" })?.items.count ?? 0,
            captionCount: request.source.tracks.first(where: { $0.role == "captions" })?.items.count ?? 0,
            includedSubRip: request.includesSubRip, loudness: loudness,
            loudnessVerified: outcome.verified, appliedGainDb: outcome.appliedGainDb,
            speechCoverage: TimelineReview.speechCoverage(request.source), completedAt: Date(),
            comparison: nil)
        if let snapshot = try? ExportHistoryStore().record(report.storedMetrics, projectRoot: request.root) {
            exportReport = ExportReport(snapshot: snapshot) ?? report
        } else {
            exportReport = report
        }
        DebugLog.write("export", "done \(outcome.receipt.url.path)")
        message = String(localized: "Export complete")
        // Keep the report for later when more exports are waiting.
        if !exports.isRunning { ui.showExportReport = true }
    }

    func restoreExportReport() {
        guard let root = fileURL?.deletingLastPathComponent(),
            let snapshot = try? ExportHistoryStore().latest(projectRoot: root)
        else { return }
        exportReport = ExportReport(snapshot: snapshot)
    }
}
