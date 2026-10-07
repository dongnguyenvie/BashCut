import BashCutPlugins
import BashCutProject
import Foundation
import Observation

/// One long-running request: a plugin capability call or an export. Automation starts it, returns
/// its ID at once and the caller polls `jobs.status`.
public struct Job: Identifiable, Sendable, Equatable {
    public enum State: String, Sendable { case queued, running, completed, failed, cancelled }

    public let id: String
    public let method: String
    public let author: Author
    public let createdAt: Date
    public internal(set) var state: State
    /// 0…1 when the job reports progress.
    public internal(set) var progress: Double?
    /// Current step or output, for status lines.
    public internal(set) var detail: String?
    public internal(set) var result: JSONValue = .null
    public internal(set) var error: String?
    public internal(set) var finishedAt: Date?
    /// When the work started running (a queued job waits before it).
    public internal(set) var runningAt: Date?
    /// The caller's stable ID for this request (P2-G4): sending it again returns this job instead of a new one.
    public internal(set) var requestID: String?
    /// What the plugin providers this job called reported using and charging.
    public let usage = PluginUsageRecorder()

    public var isActive: Bool { state == .queued || state == .running }

    /// Seconds the work has run, until now while it runs; nil while queued.
    public func wallSeconds(now: Date = Date()) -> Double? {
        runningAt.map { ((finishedAt ?? now).timeIntervalSince($0) * 1000).rounded() / 1000 }
    }

    public var json: JSONValue {
        let formatter = ISO8601DateFormatter()
        var usage = usage.json
        usage["wallSec"] = wallSeconds().map(JSONValue.number) ?? .null
        return .object([
            "id": .string(id), "method": .string(method), "author": .string(author.rawValue),
            "state": .string(state.rawValue), "progress": progress.map(JSONValue.number) ?? .null,
            "step": detail.map(JSONValue.string) ?? .null, "detail": detail.map(JSONValue.string) ?? .null,
            "result": result, "error": error.map(JSONValue.string) ?? .null, "usage": .object(usage),
            "requestId": requestID.map(JSONValue.string) ?? .null,
            "startedAt": .string(formatter.string(from: createdAt)),
            "finishedAt": finishedAt.map { .string(formatter.string(from: $0)) } ?? .null,
        ])
    }
}

/// Lets running work report progress to its job.
@MainActor
public struct JobReporter {
    public let id: String
    weak var center: JobCenter?

    public func progress(_ value: Double, detail: String? = nil) {
        center?.update(id) { job in
            job.progress = min(1, max(0, value))
            if let detail { job.detail = detail }
        }
    }

    public func detail(_ value: String) { center?.update(id) { $0.detail = value } }

    /// A thread-safe progress callback for engines that report off the main actor.
    public func progressHandler(range: ClosedRange<Double> = 0...1) -> @Sendable (Double) -> Void {
        let reporter = self
        return { value in
            Task { @MainActor in
                reporter.progress(range.lowerBound + value * (range.upperBound - range.lowerBound))
            }
        }
    }
}

/// The single job center for capability calls and exports: one list for `jobs.status`, one
/// `cancel` for `jobs.cancel`, and one place that drops everything when the project changes.
@MainActor @Observable
public final class JobCenter {
    public private(set) var jobs: [Job] = []
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var cancelHandlers: [String: @MainActor (String) -> Void] = [:]
    /// Finished jobs kept for `jobs.status`.
    public let historyLimit: Int
    /// Called once for every job that completes, fails or is cancelled while running (plugin hooks).
    @ObservationIgnored public var onFinished: (@MainActor (Job) -> Void)?

    public init(historyLimit: Int = 20) { self.historyLimit = historyLimit }

    public func job(_ id: String) -> Job? { jobs.first { $0.id == id } }

    /// The kept job `method` started for `requestID`, running or finished (finished ones stay while in the history).
    public func job(method: String, requestID: String) -> Job? {
        jobs.last { $0.method == method && $0.requestID == requestID }
    }

    /// Waits until job `id`'s state or step changes, it finishes, or `duration` passes, checking every `interval`;
    /// returns it and whether it changed, or nil when it is gone (`cancelAll`). Progress alone does not end the wait.
    public func wait(_ id: String, for duration: Duration, interval: Duration = .milliseconds(100)) async throws
        -> (job: Job, changed: Bool)?
    {
        guard let start = job(id) else { return nil }
        let deadline = ContinuousClock.now + duration
        var current = start
        while current.isActive, current.state == start.state, current.detail == start.detail,
            ContinuousClock.now < deadline
        {
            try await Task.sleep(for: interval)
            guard let next = job(id) else { return nil }
            current = next
        }
        return (current, current.state != start.state || current.detail != start.detail)
    }

    /// Adds a job that waits until `run` starts it. `onCancel` runs if it is cancelled while queued.
    @discardableResult
    public func enqueue(
        _ method: String, author: Author, detail: String? = nil, requestID: String? = nil,
        onCancel: @escaping @MainActor (_ id: String) -> Void = { _ in }
    ) -> String {
        let id = UUID().uuidString
        var job = Job(id: id, method: method, author: author, createdAt: Date(), state: .queued, detail: detail)
        job.requestID = requestID
        jobs.append(job)
        cancelHandlers[id] = onCancel
        trimHistory()
        return id
    }

    /// Starts `work` now as a new job and returns its ID.
    @discardableResult
    public func start(
        _ method: String, author: Author, detail: String? = nil, requestID: String? = nil,
        work: @escaping @MainActor (JobReporter) async throws -> JSONValue,
        finished: @escaping @MainActor (Result<JSONValue, any Error>) -> Void = { _ in }
    ) -> String {
        let id = enqueue(method, author: author, detail: detail, requestID: requestID)
        run(id, work: work, finished: finished)
        return id
    }

    /// Runs a queued job. `finished` is called once, unless the job was dropped by `cancelAll`.
    public func run(
        _ id: String, work: @escaping @MainActor (JobReporter) async throws -> JSONValue,
        finished: @escaping @MainActor (Result<JSONValue, any Error>) -> Void = { _ in }
    ) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), jobs[index].state == .queued else { return }
        jobs[index].state = .running
        jobs[index].runningAt = Date()
        cancelHandlers[id] = nil
        let reporter = JobReporter(id: id, center: self)
        // Plugin calls inside the work report usage to this job and carry its request ID.
        let call = PluginCallContext(usage: jobs[index].usage, requestID: jobs[index].requestID)
        tasks[id] = Task { [weak self] in
            let outcome: Result<JSONValue, any Error>
            do {
                outcome = .success(try await PluginCallContext.$current.withValue(call) { try await work(reporter) })
            } catch { outcome = .failure(error) }
            let cancelled = Task.isCancelled
            guard let self, self.tasks[id] != nil else { return }
            self.complete(id, outcome: outcome, cancelled: cancelled)
            finished(outcome)
        }
    }

    /// Cancels a queued or running job. Returns false when the job is unknown or already finished.
    @discardableResult
    public func cancel(_ id: String) -> Bool {
        guard let index = jobs.firstIndex(where: { $0.id == id }), jobs[index].isActive else { return false }
        if let task = tasks[id] {
            task.cancel()
        } else {
            let handler = cancelHandlers.removeValue(forKey: id)
            jobs[index].state = .cancelled
            jobs[index].finishedAt = Date()
            handler?(id)
        }
        return true
    }

    /// Cancels everything and forgets all jobs (project switch). No `finished` callbacks run.
    public func cancelAll() {
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        cancelHandlers.removeAll()
        jobs.removeAll()
    }

    func update(_ id: String, _ change: (inout Job) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), jobs[index].state == .running else { return }
        change(&jobs[index])
    }

    private func complete(_ id: String, outcome: Result<JSONValue, any Error>, cancelled: Bool) {
        tasks[id] = nil
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].finishedAt = Date()
        switch outcome {
        case .success(let value):
            jobs[index].state = .completed
            jobs[index].result = value
            jobs[index].progress = jobs[index].progress.map { _ in 1 }
        case .failure(let error):
            jobs[index].state = cancelled || Self.isCancellation(error) ? .cancelled : .failed
            jobs[index].error = error.localizedDescription
        }
        let job = jobs[index]
        trimHistory()
        onFinished?(job)
    }

    private func trimHistory() {
        let finished = jobs.filter { !$0.isActive }
        let excess = finished.count - historyLimit
        guard excess > 0 else { return }
        let dropped = Set(finished.prefix(excess).map(\.id))
        jobs.removeAll { dropped.contains($0.id) }
    }

    public static func isCancellation(_ error: any Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
            || error.localizedDescription == "Plugin request was cancelled"
    }
}
