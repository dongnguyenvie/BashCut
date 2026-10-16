import BashCutEngine
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
    /// The toast about the latest export starting, finishing or failing; nil once dismissed or timed out.
    public private(set) var notice: ExportNotice?
    /// The newest export of this session that failed, until one finishes after it: `export.status` reports it as
    /// `failed` with its error, so a caller polling the status sees the failure instead of the older receipt.
    public private(set) var failure: ExportFailure?
    /// Plugin export steps running before the exports start (#634); the export counts as running meanwhile.
    public private(set) var preparing: ExportPreparation?
    /// Keeps App Nap off while export steps run, as the queue does for the export itself (#350): a step can run for
    /// minutes and calls back into the app through the CLI.
    @ObservationIgnored private var preparingActivity: (any NSObjectProtocol)?
    @ObservationIgnored private let history: ExportHistoryStore

    public init(
        jobs: JobCenter, history: ExportHistoryStore = ExportHistoryStore(),
        pipeline: @escaping @MainActor () -> ExportPipeline
    ) {
        queue = ExportQueue(jobs: jobs, pipeline: pipeline)
        self.history = history
    }

    public var isRunning: Bool { queue.isRunning || preparing != nil }
    public var progress: Double {
        preparing.map { queue.jobs.job($0.job)?.progress ?? 0 } ?? queue.progress
    }
    /// The running export step's job, while one runs.
    public var preparingJob: Job? { preparing.flatMap { queue.jobs.job($0.job) } }

    /// The export steps job `job` runs before exporting `name`; `endPreparing` when it is over.
    public func beginPreparing(job: String, name: String, steps: [String]) {
        preparing = ExportPreparation(job: job, name: name, steps: steps)
        if preparingActivity == nil {
            preparingActivity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiated, reason: "Running export steps")
        }
    }

    public func endPreparing() {
        preparing = nil
        if let preparingActivity { ProcessInfo.processInfo.endActivity(preparingActivity) }
        preparingActivity = nil
    }

    /// Queues `request`. When it finishes, the report is recorded first, then `finished` runs with the
    /// outcome; it does not run after `reset`.
    @discardableResult
    public func enqueue(
        _ request: ExportRequest, author: Author,
        finished: @escaping @MainActor (Result<ExportOutcome, any Error>) -> Void
    ) throws -> String {
        try queue.enqueue(request, author: author) { [weak self] result in
            switch result {
            case .success(let outcome):
                self?.failure = nil
                self?.record(request, outcome: outcome)
            case .failure(let error) where !JobCenter.isCancellation(error):
                self?.failure = ExportFailure(
                    preset: request.preset.rawValue, path: request.output.path, error: error.localizedDescription, at: Date())
            case .failure: break
            }
            finished(result)
        }
    }

    /// Cancels the running export, or the export steps before it (then nothing is exported); queued exports start
    /// next.
    public func cancelActive() {
        if let preparing { queue.jobs.cancel(preparing.job) } else { queue.cancelActive() }
    }

    /// Drops every export and the report when another project opens.
    public func reset() {
        if let preparing { queue.jobs.cancel(preparing.job) }
        endPreparing()
        queue.cancelAll()
        report = nil
        notice = nil
        failure = nil
    }

    /// Shows `notice`; it hides by itself after its kind's delay unless a newer notice replaced it.
    public func post(_ notice: ExportNotice) {
        self.notice = notice
        guard let delay = notice.kind.hideAfter else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            if self?.notice?.id == notice.id { self?.notice = nil }
        }
    }

    public func dismissNotice() { notice = nil }

    /// Shows the last export recorded in the project's export history, if any.
    public func restoreReport(projectRoot: URL) {
        guard let snapshot = try? history.latest(projectRoot: projectRoot) else { return }
        report = ExportReport(snapshot: snapshot)
    }

    private func record(_ request: ExportRequest, outcome: ExportOutcome) {
        var report = ExportReport(
            receipt: outcome.receipt, preset: request.preset,
            cutCount: request.source.tracks.first(where: { $0.role == TrackRole.main })?.items.count ?? 0,
            captionCount: request.source.tracks.first(where: { $0.role == TrackRole.captions })?.items.count ?? 0,
            includedSubRip: request.includesSubRip, loudness: outcome.finalMeasurement,
            loudnessVerified: outcome.verified, appliedGainDb: outcome.appliedGainDb,
            speechCoverage: outcome.speechCoverage,
            completedAt: Date(),
            comparison: nil)
        report.acceptedIssues = (request.source["review"]?.object["accepted"]?.object ?? [:])
            .compactMapValues { $0.object["reason"]?.string }
        if let snapshot = try? history.record(report.storedMetrics, projectRoot: request.root, project: request.source) {
            self.report = ExportReport(snapshot: snapshot) ?? report
        } else {
            self.report = report
        }
    }

    /// The project's export ledger (P3-I2).
    public var ledger: ExportHistoryStore { history }

    /// `export.status`: while an export runs, the top-level fields describe it and the last receipt
    /// moves to `lastExport`.
    public var statusJSON: JSONValue {
        var result: [String: JSONValue] = ["queue": .array(queue.active.map(\.json))]
        let last = report.map(\.json)
        if let preparing, let job = preparingJob {
            result["state"] = .string("preparing")
            result["progress"] = .number(job.progress ?? 0)
            result["job"] = .string(job.id)
            result["step"] = job.detail.map(JSONValue.string) ?? .null
            result["exportSteps"] = .array(preparing.steps.map(JSONValue.string))
            result["lastExport"] = last.map(JSONValue.object) ?? .null
            return .object(result)
        }
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
        if let failure {
            result["state"] = .string("failed")
            result["progress"] = .number(0)
            result["preset"] = .string(failure.preset)
            result["path"] = .string(failure.path)
            result["error"] = .string(failure.error)
            result["failedAt"] = .string(ISO8601DateFormatter().string(from: failure.at))
            result["lastExport"] = last.map(JSONValue.object) ?? .null
            return .object(result)
        }
        result["state"] = .string(report == nil ? "idle" : "completed")
        result["progress"] = .number(report == nil ? 0 : 1)
        return .object(result.merging(last ?? [:]) { current, _ in current })
    }
}

/// Plugin export steps running before an export (#634): their job, the export's name and the steps' titles.
public struct ExportPreparation: Equatable, Sendable {
    public let job: String
    public let name: String
    public let steps: [String]
}

/// An export that failed (not cancelled): its preset, the file it was writing and the error.
public struct ExportFailure: Equatable, Sendable {
    public let preset: String
    public let path: String
    public let error: String
    public let at: Date
}

/// What the export toast says: an export started or was queued, finished, failed or was cancelled.
public struct ExportNotice: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case started, queued, finished, cancelled
        case failed(String)

        /// Seconds before the toast hides by itself; failures stay until dismissed.
        var hideAfter: Double? {
            switch self {
            case .started, .queued, .cancelled: 6
            case .finished: 12
            case .failed: nil
            }
        }
    }

    public let id = UUID()
    public let kind: Kind
    /// The output file name, such as `long1.mp4`.
    public let name: String
    public let author: Author

    public init(_ kind: Kind, name: String, author: Author) {
        self.kind = kind
        self.name = name
        self.author = author
    }
}
