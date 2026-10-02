import AppKit
import BashCutAutomation
import BashCutEngine
import BashCutInterchange
import BashCutPlugin
import BashCutProject
import BashCutStorage
import Foundation

private struct PreparedExport: Sendable {
    let source: Project
    let project: Project
    let root: URL
    let output: URL
    let subRip: URL
    let captionText: String?
    let preset: ExportPreset
    let includeSubRip: Bool
    let normalizeAudio: Bool
}

private struct CompletedExport: Sendable {
    let receipt: ExportReceipt
    let generated: GeneratedLoudnessMeasurement?
    let finalMeasurement: LoudnessMeasurement?
    let verified: Bool
    let mixGainDb: Double?
    let appliedGainDb: Double?
}

extension ProjectDocument {
    func export() { showExport = true }

    func exportOTIO() {
        guard fileURL != nil else {
            message = String(localized: "Save the project before exporting")
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "otio")].compactMap { $0 }
        panel.nameFieldStringValue = project.name + ".otio"
        panel.directoryURL = fileURL?.deletingLastPathComponent().appendingPathComponent("render")
        guard panel.runModal() == .OK, let url = panel.url else { return }
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

    func startExportAuthorized(
        name: String, preset: ExportPreset, directory: URL, includeSubRip: Bool,
        normalizeAudio: Bool = false
    ) throws {
        guard !exporting else { throw RPCFailure(-32003, "An export is already running") }
        let prepared = try prepareExport(
            name: name, preset: preset, directory: directory, includeSubRip: includeSubRip,
            normalizeAudio: normalizeAudio)
        launchExport(prepared)
    }

    func cancelExport() { exportTask?.cancel() }

    private func prepareExport(
        name: String, preset: ExportPreset, directory: URL, includeSubRip: Bool,
        normalizeAudio: Bool
    ) throws -> PreparedExport {
        guard let root = fileURL?.deletingLastPathComponent() else {
            throw ProjectError.invalid("Save the project before exporting")
        }
        let baseName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseName.isEmpty, !baseName.contains("/"), !baseName.contains(":"), baseName.count <= 180 else {
            throw ProjectError.invalid("Use a file name without slashes or colons")
        }
        let output = directory.appendingPathComponent(baseName).appendingPathExtension(preset.fileExtension)
        let subRip = directory.appendingPathComponent(baseName).appendingPathExtension("srt")
        guard !FileManager.default.fileExists(atPath: output.path),
            !includeSubRip || !FileManager.default.fileExists(atPath: subRip.path)
        else { throw ProjectError.invalid("Choose a new export name; an output already exists") }
        let source = project
        let dimensions = preset.dimensions(projectWidth: source.width, projectHeight: source.height)
        var exportProject = source
        var format = exportProject["format"]?.object ?? [:]
        format["width"] = .integer(dimensions.0)
        format["height"] = .integer(dimensions.1)
        exportProject["format"] = .object(format)
        let captionText = includeSubRip ? try SubRip.encode(source) : nil
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return PreparedExport(
            source: source, project: exportProject, root: root, output: output, subRip: subRip,
            captionText: captionText, preset: preset, includeSubRip: includeSubRip,
            normalizeAudio: normalizeAudio)
    }

    private func launchExport(_ prepared: PreparedExport) {
        let session = sessionID
        exporting = true
        exportProgress = 0
        exportReport = nil
        showExport = false
        message = String(localized: "Preparing export…")
        exportTask = Task {
            defer {
                if session == sessionID { exporting = false }
            }
            do {
                let completed = try await performExport(prepared, session: session)
                try Task.checkCancellation()
                if let text = prepared.captionText {
                    try text.write(to: prepared.subRip, atomically: true, encoding: .utf8)
                }
                finishExport(prepared, completed: completed, session: session)
            } catch is CancellationError {
                if session == sessionID { message = String(localized: "Export cancelled") }
            } catch {
                if session == sessionID { message = error.localizedDescription }
            }
        }
    }

    private func performExport(_ prepared: PreparedExport, session: UUID) async throws
        -> CompletedExport
    {
        if prepared.normalizeAudio {
            plugins.refresh(projectRoot: prepared.root)
            guard !plugins.providers(for: "audio.loudness").isEmpty else {
                throw ProjectError.invalid("Install a plugin that provides audio.loudness")
            }
        }
        let snapshot = try await engine.build(
            prepared.project, root: prepared.root, workspace: agents.workspace)
        try Task.checkCancellation()
        guard prepared.normalizeAudio else {
            let receipt = try await exportSnapshot(
                snapshot, to: prepared.output, preset: prepared.preset, progress: 0...1, session: session)
            return CompletedExport(
                receipt: receipt, generated: nil, finalMeasurement: nil, verified: false,
                mixGainDb: nil, appliedGainDb: nil)
        }
        let temporaryDirectory = prepared.root.appendingPathComponent(".bashcut/loudness", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let temporary = temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(prepared.preset.fileExtension)
        defer { try? FileManager.default.removeItem(at: temporary) }
        _ = try await exportSnapshot(
            snapshot, to: temporary, preset: prepared.preset, progress: 0...0.42, session: session)
        if session == sessionID { message = String(localized: "Measuring loudness…") }
        let preferred = prepared.source.preferredProvider(for: "audio.loudness")
        let measured = try await plugins.analyzeLoudness(
            mediaURL: temporary, preferredProvider: preferred)
        let requestedCorrection = try LoudnessNormalizer.correction(
            measurement: measured.measurement, targetLUFS: prepared.source.targetLUFS)
        let currentMixGain = prepared.project.mixGainDb
        let mixGain = max(-60, min(24, currentMixGain + requestedCorrection))
        let appliedGain = mixGain - currentMixGain
        var normalizedProject = prepared.project
        var audio = normalizedProject["audio"]?.object ?? [:]
        audio["mixGainDb"] = .number(mixGain)
        normalizedProject["audio"] = .object(audio)
        let normalizedSnapshot = try await engine.build(
            normalizedProject, root: prepared.root, workspace: agents.workspace)
        let receipt = try await exportSnapshot(
            normalizedSnapshot, to: prepared.output, preset: prepared.preset,
            progress: 0.48...0.96, session: session)
        if session == sessionID { message = String(localized: "Verifying loudness…") }
        let final: LoudnessMeasurement
        let verified: Bool
        do {
            final = try await plugins.analyzeLoudness(
                mediaURL: prepared.output, preferredProvider: preferred
            ).measurement
            verified = true
        } catch {
            final = LoudnessMeasurement(
                integratedLUFS: measured.measurement.integratedLUFS + appliedGain,
                truePeakDbTP: measured.measurement.truePeakDbTP + appliedGain,
                loudnessRangeLU: measured.measurement.loudnessRangeLU)
            verified = false
        }
        return CompletedExport(
            receipt: receipt, generated: measured, finalMeasurement: final,
            verified: verified, mixGainDb: mixGain, appliedGainDb: appliedGain)
    }

    private func exportSnapshot(
        _ snapshot: CompositionSnapshot, to output: URL, preset: ExportPreset,
        progress range: ClosedRange<Double>, session: UUID
    ) async throws -> ExportReceipt {
        try await engine.export(snapshot, to: output, settings: ExportSettings(preset: preset)) { [weak self] value in
            Task { @MainActor in
                guard self?.sessionID == session else { return }
                self?.exportProgress = range.lowerBound + value * (range.upperBound - range.lowerBound)
            }
        }
    }

    private func finishExport(_ prepared: PreparedExport, completed: CompletedExport, session: UUID) {
        guard session == sessionID else { return }
        let loudness = completed.finalMeasurement
        if let generated = completed.generated, let mixGain = completed.mixGainDb,
            project.revision == prepared.source.revision
        {
            var audio = project["audio"]?.object ?? [:]
            audio["mixGainDb"] = .number(mixGain)
            if let loudness {
                audio["measuredLUFS"] = .number(loudness.integratedLUFS)
                audio["truePeakDbTP"] = .number(loudness.truePeakDbTP)
            }
            audio["measurementVerified"] = .bool(completed.verified)
            if let range = loudness?.loudnessRangeLU { audio["loudnessRangeLU"] = .number(range) }
            audio["measuredBy"] = .object([
                "plugin": .string(generated.pluginID),
                "provider": .string(generated.providerID),
                "version": .string(generated.pluginVersion),
            ])
            apply(.setProjectProperties(patch: ["audio": .object(audio)]), label: "Normalize audio")
        }
        exportProgress = 1
        let report = ExportReport(
            receipt: completed.receipt, preset: prepared.preset,
            cutCount: prepared.source.tracks.first(where: { $0.role == "main" })?.items.count ?? 0,
            captionCount: prepared.source.tracks.first(where: { $0.role == "captions" })?.items.count ?? 0,
            includedSubRip: prepared.includeSubRip, loudness: loudness,
            loudnessVerified: completed.verified, appliedGainDb: completed.appliedGainDb,
            speechCoverage: TimelineReview.speechCoverage(prepared.source), completedAt: Date(),
            comparison: nil)
        if let snapshot = try? ExportHistoryStore().record(
            report.storedMetrics, projectRoot: prepared.root)
        {
            exportReport = ExportReport(snapshot: snapshot) ?? report
        } else {
            exportReport = report
        }
        message = String(localized: "Export complete")
        showExportReport = true
    }

    func restoreExportReport() {
        guard let root = fileURL?.deletingLastPathComponent(),
            let snapshot = try? ExportHistoryStore().latest(projectRoot: root)
        else { return }
        exportReport = ExportReport(snapshot: snapshot)
        if exportReport != nil { exportProgress = 1 }
    }
}
