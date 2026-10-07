import BashCutProject
import Foundation
import Observation

/// Background export queue on the shared job center: exports run one at a time in request order,
/// each as an `export.start` job that `jobs.status` lists and `jobs.cancel` stops.
@MainActor @Observable
public final class ExportQueue {
    public static let method = "export.start"

    private struct Pending {
        let job: String
        let request: ExportRequest
        let finished: @MainActor (Result<ExportOutcome, any Error>) -> Void
    }

    public let jobs: JobCenter
    @ObservationIgnored private let pipeline: @MainActor () -> ExportPipeline
    @ObservationIgnored private var pending: [Pending] = []
    @ObservationIgnored private var requests: [String: ExportRequest] = [:]
    @ObservationIgnored private var outcomes: [String: ExportOutcome] = [:]
    public private(set) var activeJob: String?

    /// `pipeline` is read when each export starts, so plugin changes apply to queued exports.
    public init(jobs: JobCenter, pipeline: @escaping @MainActor () -> ExportPipeline) {
        self.jobs = jobs
        self.pipeline = pipeline
    }

    /// Export jobs still waiting or running, oldest first.
    public var active: [Job] { jobs.jobs.filter { $0.method == Self.method && $0.isActive } }
    public var queuedCount: Int { active.filter { $0.state == .queued }.count }
    public var isRunning: Bool { activeJob != nil }
    public var progress: Double { activeJob.flatMap { jobs.job($0)?.progress } ?? 0 }
    /// Output name or current step of the running export.
    public var detail: String? { activeJob.flatMap { jobs.job($0)?.detail } }

    /// Files that queued or running exports will write.
    public var reservedOutputs: Set<URL> { Set(requests.values.flatMap(\.outputs)) }

    public func request(for job: String) -> ExportRequest? { requests[job] }

    /// Queues `request` and returns its job ID. `finished` runs on completion, failure or
    /// cancellation, but not after `cancelAll`.
    @discardableResult
    public func enqueue(
        _ request: ExportRequest, author: Author,
        finished: @escaping @MainActor (Result<ExportOutcome, any Error>) -> Void
    ) throws -> String {
        guard reservedOutputs.isDisjoint(with: request.outputs) else {
            throw ProjectError.invalid("Choose a new export name; an output already exists or is queued")
        }
        let id = jobs.enqueue(Self.method, author: author, detail: request.output.lastPathComponent) { [weak self] id in
            self?.dropPending(id)
            finished(.failure(CancellationError()))
        }
        requests[id] = request
        pending.append(Pending(job: id, request: request, finished: finished))
        startNext()
        return id
    }

    /// Cancels the running export; queued ones continue.
    public func cancelActive() {
        if let activeJob { jobs.cancel(activeJob) }
    }

    /// Drops every queued and running export (project switch). The job center is cleared separately.
    public func cancelAll() {
        if let activeJob { jobs.cancel(activeJob) }
        pending.removeAll()
        requests.removeAll()
        outcomes.removeAll()
        activeJob = nil
    }

    private func dropPending(_ id: String) {
        pending.removeAll { $0.job == id }
        requests[id] = nil
    }

    private func startNext() {
        guard activeJob == nil, !pending.isEmpty else { return }
        let next = pending.removeFirst()
        activeJob = next.job
        let pipeline = pipeline()
        let request = next.request
        let id = next.job
        jobs.run(id, work: { [weak self] reporter in
            reporter.progress(0, detail: request.output.lastPathComponent)
            let handler = reporter.progressHandler()
            let detailReporter = reporter
            let result = try await pipeline.run(request) { value, step in
                handler(value)
                if let step { Task { @MainActor in detailReporter.detail(step) } }
            }
            self?.outcomes[id] = result
            var receipt: [String: JSONValue] = [
                "path": .string(result.receipt.url.path), "duration": .number(result.receipt.duration),
                "bytes": .integer(Int(result.receipt.bytes)),
            ]
            // What the file owes for the media it plays, for its platform (P2-H9), when the project asks for it.
            if ReviewProfile(request.project).credits {
                receipt["credits"] = ProjectCredits.of(request.project, platforms: [request.preset.platform].compactMap { $0 }).json
            }
            return .object(receipt)
        }, finished: { [weak self] result in
            guard let self else { return }
            let outcome = outcomes.removeValue(forKey: id)
            finish(next, result: result.flatMap { _ in
                outcome.map { .success($0) } ?? .failure(CancellationError())
            })
        })
    }

    private func finish(_ export: Pending, result: Result<ExportOutcome, any Error>) {
        guard activeJob == export.job else { return }
        activeJob = nil
        requests[export.job] = nil
        export.finished(result)
        startNext()
    }
}
