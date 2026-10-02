import BashCutEngine
import BashCutInterchange
import BashCutPlugin
import BashCutProject
import BashCutStorage
import Foundation
import Observation

/// Video and OTIO exports for one document: the background queue, the report of the last finished
/// export (kept in the project's export history) and the `export.status` description.
@MainActor @Observable
public final class ExportController {
    public let queue: ExportQueue
    /// The last finished export of the open project, restored from its export history on open.
    public private(set) var report: ExportReport?
    @ObservationIgnored private let history: ExportHistoryStore

    public init(
        jobs: JobCenter, history: ExportHistoryStore = ExportHistoryStore(),
        pipeline: @escaping @MainActor () -> ExportPipeline
    ) {
        queue = ExportQueue(jobs: jobs, pipeline: pipeline)
        self.history = history
    }

    public var isRunning: Bool { queue.isRunning }
    public var progress: Double { queue.progress }

    /// Queues `request`. When it finishes, the report is recorded first, then `finished` runs with the
    /// outcome; it does not run after `reset`.
    @discardableResult
    public func enqueue(
        _ request: ExportRequest, author: Author,
        finished: @escaping @MainActor (Result<ExportOutcome, any Error>) -> Void
    ) throws -> String {
        try queue.enqueue(request, author: author) { [weak self] result in
            if case .success(let outcome) = result { self?.record(request, outcome: outcome) }
            finished(result)
        }
    }

    /// Cancels the running export; queued exports start next.
    public func cancelActive() { queue.cancelActive() }

    /// Drops every export and the report when another project opens.
    public func reset() {
        queue.cancelAll()
        report = nil
    }

    /// Shows the last export recorded in the project's export history, if any.
    public func restoreReport(projectRoot: URL) {
        guard let snapshot = try? history.latest(projectRoot: projectRoot) else { return }
        report = ExportReport(snapshot: snapshot)
    }

    private func record(_ request: ExportRequest, outcome: ExportOutcome) {
        let report = ExportReport(
            receipt: outcome.receipt, preset: request.preset,
            cutCount: request.source.tracks.first(where: { $0.role == TrackRole.main })?.items.count ?? 0,
            captionCount: request.source.tracks.first(where: { $0.role == TrackRole.captions })?.items.count ?? 0,
            includedSubRip: request.includesSubRip, loudness: outcome.finalMeasurement,
            loudnessVerified: outcome.verified, appliedGainDb: outcome.appliedGainDb,
            speechCoverage: TimelineReview.speechCoverage(request.source), completedAt: Date(),
            comparison: nil)
        if let snapshot = try? history.record(report.storedMetrics, projectRoot: request.root) {
            self.report = ExportReport(snapshot: snapshot) ?? report
        } else {
            self.report = report
        }
    }

    /// The project's `audio` properties after a normalized export, or nil when the export did not
    /// measure loudness with a plugin.
    public static func normalizedAudio(_ outcome: ExportOutcome, current: JSONValue?) -> JSONValue? {
        guard let generated = outcome.generated, let mixGain = outcome.mixGainDb else { return nil }
        let loudness = outcome.finalMeasurement
        var audio = current?.object ?? [:]
        audio["mixGainDb"] = .number(mixGain)
        if let loudness {
            audio["measuredLUFS"] = .number(loudness.integratedLUFS)
            audio["truePeakDbTP"] = .number(loudness.truePeakDbTP)
        }
        audio["measurementVerified"] = .bool(outcome.verified)
        if let range = loudness?.loudnessRangeLU { audio["loudnessRangeLU"] = .number(range) }
        audio["measuredBy"] = .object(generated.provenance.json)
        return .object(audio)
    }

    /// Writes `project` as OpenTimelineIO, refusing to replace a file unless `allowReplace`.
    public static func writeOTIO(_ project: Project, to url: URL, allowReplace: Bool = false) throws {
        guard allowReplace || !FileManager.default.fileExists(atPath: url.path) else {
            throw ProjectError.invalid("Choose a new export name; an output already exists")
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try OpenTimelineIOExporter.data(for: project).write(to: url, options: .atomic)
    }

    /// `export.status`: while an export runs, the top-level fields describe it and the last receipt
    /// moves to `lastExport`.
    public var statusJSON: JSONValue {
        var result: [String: JSONValue] = ["queue": .array(queue.active.map(\.json))]
        let last = report.map(\.json)
        if let job = queue.activeJob, let request = queue.request(for: job) {
            result["state"] = .string("running")
            result["progress"] = .number(progress)
            result["job"] = .string(job)
            result["step"] = queue.detail.map(JSONValue.string) ?? .null
            result["preset"] = .string(request.preset.rawValue)
            result["path"] = .string(request.output.path)
            result["includedSRT"] = .bool(request.includesSubRip)
            result["normalizeAudio"] = .bool(request.normalizeAudio)
            result["lastExport"] = last.map(JSONValue.object) ?? .null
            return .object(result)
        }
        result["state"] = .string(report == nil ? "idle" : "completed")
        result["progress"] = .number(report == nil ? 0 : 1)
        return .object(result.merging(last ?? [:]) { current, _ in current })
    }
}
