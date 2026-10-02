import BashCutEngine
import BashCutProject
import Foundation
import Observation

/// Generates preview proxies one at a time as `media.proxy` jobs on the shared job center, so importing
/// many heavy clips does not start many encoders at once. A file already queued or running is not queued
/// twice; `onFinished` reports each proxy that was written so the preview can pick it up.
@MainActor @Observable
public final class ProxyQueue {
    public static let method = "media.proxy"
    public typealias Generate = @Sendable (_ source: URL, _ destination: URL, _ progress: @escaping @Sendable (Double) -> Void)
        async throws -> Void

    private struct Pending {
        let job: String
        let source: URL
        let destination: URL
    }

    public let jobs: JobCenter
    @ObservationIgnored private let generate: Generate
    @ObservationIgnored private var pending: [Pending] = []
    @ObservationIgnored private var running: Pending?
    @ObservationIgnored public var onFinished: (@MainActor (URL) -> Void)?

    public init(jobs: JobCenter, generate: @escaping Generate = { source, destination, progress in
        try await ProxyManager().generate(from: source, to: destination, progress: progress)
    }) {
        self.jobs = jobs
        self.generate = generate
    }

    /// Queued and running proxy jobs, oldest first.
    public var active: [Job] { jobs.jobs.filter { $0.method == Self.method && $0.isActive } }

    /// Queues a proxy for `source` at `destination` and returns its job ID, or the existing job's ID when
    /// that destination is already queued or running.
    @discardableResult
    public func request(source: URL, destination: URL, label: String, author: Author) -> String {
        if let existing = ([running].compactMap { $0 } + pending).first(where: { $0.destination == destination }) {
            return existing.job
        }
        let id = jobs.enqueue(Self.method, author: author, detail: label) { [weak self] id in
            self?.pending.removeAll { $0.job == id }
        }
        pending.append(Pending(job: id, source: source, destination: destination))
        startNext()
        return id
    }

    /// Drops queued and running proxies (project switch). The job center is cleared separately.
    public func cancelAll() {
        if let running { jobs.cancel(running.job) }
        pending.removeAll()
        running = nil
    }

    private func startNext() {
        guard running == nil, !pending.isEmpty else { return }
        let next = pending.removeFirst()
        running = next
        let generate = generate
        jobs.run(next.job, work: { reporter in
            try await generate(next.source, next.destination, reporter.progressHandler())
            return .object(["path": .string(next.destination.path)])
        }, finished: { [weak self] result in
            guard let self, running?.job == next.job else { return }
            running = nil
            if case .success = result { onFinished?(next.destination) }
            startNext()
        })
    }
}
