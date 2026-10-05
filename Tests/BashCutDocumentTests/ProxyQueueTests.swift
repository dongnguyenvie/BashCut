import BashCutDocument
import BashCutProject
import Foundation
import Testing

@MainActor
struct ProxyQueueTests {
    /// Records which proxies started and lets the test finish them one by one.
    private final class FakeEncoder: @unchecked Sendable {
        private let lock = NSLock()
        private var started: [String] = []
        private var gates: [String: CheckedContinuation<Void, any Error>] = [:]

        var startedNames: [String] { lock.withLock { started } }

        func generate(_ source: URL, _ destination: URL, _ progress: @escaping @Sendable (Double) -> Void) async throws {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock {
                    started.append(source.lastPathComponent)
                    gates[source.lastPathComponent] = continuation
                }
            }
        }

        func finish(_ name: String, failing: Bool = false) {
            let gate = lock.withLock { gates.removeValue(forKey: name) }
            if failing { gate?.resume(throwing: CancellationError()) } else { gate?.resume() }
        }
    }

    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    @Test("Proxies encode one at a time, a destination is queued once and finished proxies are reported")
    func sequential() async throws {
        let encoder = FakeEncoder()
        let jobs = JobCenter()
        let queue = ProxyQueue(jobs: jobs, generate: encoder.generate)
        var written: [String] = []
        queue.onFinished = { written.append($0.lastPathComponent) }
        let root = URL(fileURLWithPath: "/tmp/project/.bashcut/cache/proxies")
        let first = queue.request(
            source: URL(fileURLWithPath: "/footage/a.mp4"), destination: root.appendingPathComponent("a.mov"),
            label: "a.mp4", author: .user)
        let second = queue.request(
            source: URL(fileURLWithPath: "/footage/b.mp4"), destination: root.appendingPathComponent("b.mov"),
            label: "b.mp4", author: .agent)
        let again = queue.request(
            source: URL(fileURLWithPath: "/footage/b.mp4"), destination: root.appendingPathComponent("b.mov"),
            label: "b.mp4", author: .agent)
        #expect(again == second)
        await settle()
        #expect(encoder.startedNames == ["a.mp4"])
        #expect(jobs.job(second)?.state == .queued)

        encoder.finish("a.mp4")
        await settle()
        #expect(jobs.job(first)?.state == .completed)
        #expect(written == ["a.mov"])
        #expect(encoder.startedNames == ["a.mp4", "b.mp4"])

        encoder.finish("b.mp4", failing: true)
        await settle()
        #expect(jobs.job(second)?.state == .cancelled)
        #expect(written == ["a.mov"])
        #expect(queue.active.isEmpty)
    }

    @Test("Cancelling a queued proxy removes it without starting it")
    func cancelQueued() async throws {
        let encoder = FakeEncoder()
        let jobs = JobCenter()
        let queue = ProxyQueue(jobs: jobs, generate: encoder.generate)
        let root = URL(fileURLWithPath: "/tmp/project/.bashcut/cache/proxies")
        _ = queue.request(
            source: URL(fileURLWithPath: "/footage/a.mp4"), destination: root.appendingPathComponent("a.mov"),
            label: "a", author: .user)
        let second = queue.request(
            source: URL(fileURLWithPath: "/footage/b.mp4"), destination: root.appendingPathComponent("b.mov"),
            label: "b", author: .user)
        #expect(jobs.cancel(second))
        encoder.finish("a.mp4")
        await settle()
        #expect(encoder.startedNames == ["a.mp4"])
        #expect(jobs.job(second)?.state == .cancelled)
    }
}
