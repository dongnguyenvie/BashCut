import BashCutEngine
import BashCutPlugin
import BashCutPlugins
import BashCutProject
import Foundation

/// Measures integrated loudness through a plugin provider.
public protocol LoudnessAnalyzing: Sendable {
    func analyzeLoudness(
        mediaURL: URL, preferredProvider: String?, projectRoot: URL?
    ) async throws -> GeneratedLoudnessMeasurement
}

extension CapabilityService: LoudnessAnalyzing {}

/// What an export produced: the receipt plus loudness results when normalization ran.
public struct ExportOutcome: Sendable {
    public let receipt: ExportReceipt
    public let generated: GeneratedLoudnessMeasurement?
    public let finalMeasurement: LoudnessMeasurement?
    public let verified: Bool
    public let mixGainDb: Double?
    public let appliedGainDb: Double?
}

/// Renders one `ExportRequest`: build, render, optional two-pass loudness normalization, SubRip.
/// It never touches the open document; the caller applies results.
public struct ExportPipeline: Sendable {
    public let engine: any RenderEngine
    public let loudness: (any LoudnessAnalyzing)?

    public init(engine: any RenderEngine, loudness: (any LoudnessAnalyzing)?) {
        self.engine = engine
        self.loudness = loudness
    }

    /// `progress` gets 0…1 and an optional step name; it may be called off the main actor.
    public func run(
        _ request: ExportRequest, progress: @escaping @Sendable (Double, String?) -> Void
    ) async throws -> ExportOutcome {
        let outcome = try await render(request, progress: progress)
        try Task.checkCancellation()
        if let text = request.captionText, let subRip = request.subRip {
            try text.write(to: subRip, atomically: true, encoding: .utf8)
        }
        progress(1, nil)
        return outcome
    }

    private func render(
        _ request: ExportRequest, progress: @escaping @Sendable (Double, String?) -> Void
    ) async throws -> ExportOutcome {
        try FileManager.default.createDirectory(
            at: request.output.deletingLastPathComponent(), withIntermediateDirectories: true)
        let snapshot = try await engine.build(
            request.project, root: request.root, workspace: request.workspace, purpose: .export)
        try Task.checkCancellation()
        guard request.normalizeAudio else {
            let receipt = try await export(snapshot, to: request.output, request, 0...1, progress)
            return ExportOutcome(
                receipt: receipt, generated: nil, finalMeasurement: nil, verified: false,
                mixGainDb: nil, appliedGainDb: nil)
        }
        guard let loudness else { throw ProjectError.invalid("Install a plugin that provides audio.loudness") }
        let temporaryDirectory = ProjectCache.url(.loudness, projectRoot: request.root)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let temporary = temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("caf")
        defer { try? FileManager.default.removeItem(at: temporary) }
        _ = try await engine.exportAudio(snapshot, to: temporary) { value in progress(value * 0.15, nil) }
        progress(0.15, String(localized: "Measuring loudness…"))
        let preferred = request.source.preferredProvider(for: "audio.loudness")
        let measured = try await loudness.analyzeLoudness(
            mediaURL: temporary, preferredProvider: preferred, projectRoot: request.root)
        let correction = try LoudnessNormalizer.correction(
            measurement: measured.measurement, targetLUFS: request.source.targetLUFS)
        let currentMixGain = request.project.mixGainDb
        let mixGain = max(-60, min(24, currentMixGain + correction))
        let appliedGain = mixGain - currentMixGain
        var audio = request.project["audio"]?.object ?? [:]
        audio["mixGainDb"] = .number(mixGain)
        let normalized = try request.project.applying(.setProjectProperties(patch: ["audio": .object(audio)])).project
        let normalizedSnapshot = try await engine.build(
            normalized, root: request.root, workspace: request.workspace, purpose: .export)
        let receipt = try await export(normalizedSnapshot, to: request.output, request, 0.20...0.96, progress)
        progress(0.96, String(localized: "Verifying loudness…"))
        let final: LoudnessMeasurement
        let verified: Bool
        do {
            final = try await loudness.analyzeLoudness(
                mediaURL: request.output, preferredProvider: preferred, projectRoot: request.root
            ).measurement
            verified = true
        } catch {
            final = LoudnessMeasurement(
                integratedLUFS: measured.measurement.integratedLUFS + appliedGain,
                truePeakDbTP: measured.measurement.truePeakDbTP + appliedGain,
                loudnessRangeLU: measured.measurement.loudnessRangeLU)
            verified = false
        }
        return ExportOutcome(
            receipt: receipt, generated: measured, finalMeasurement: final, verified: verified,
            mixGainDb: mixGain, appliedGainDb: appliedGain)
    }

    private func export(
        _ snapshot: CompositionSnapshot, to url: URL, _ request: ExportRequest, _ range: ClosedRange<Double>,
        _ progress: @escaping @Sendable (Double, String?) -> Void
    ) async throws -> ExportReceipt {
        try await engine.export(snapshot, to: url, settings: ExportSettings(preset: request.preset)) { value in
            progress(range.lowerBound + value * (range.upperBound - range.lowerBound), nil)
        }
    }
}
