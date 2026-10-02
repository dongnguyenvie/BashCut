import AVFoundation
import BashCutDocument
import BashCutEngine
import BashCutProject
import Foundation
import Testing

/// Renders nothing: each export waits `steps` short sleeps (cancellable), then writes a stub file.
private struct FakeEngine: RenderEngine {
    let log: ExportLog
    var steps = 3

    func build(_ project: Project, root: URL, workspace: URL?) async throws -> CompositionSnapshot {
        CompositionSnapshot(
            composition: AVMutableComposition(), videoComposition: AVMutableVideoComposition(),
            audioMix: AVMutableAudioMix())
    }

    func export(
        _ snapshot: CompositionSnapshot, to url: URL, settings: ExportSettings,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> ExportReceipt {
        await log.started(url.lastPathComponent)
        for step in 1...steps {
            try await Task.sleep(for: .milliseconds(15))
            progress(Double(step) / Double(steps))
        }
        try Data("stub".utf8).write(to: url)
        await log.finished(url.lastPathComponent)
        return ExportReceipt(url: url, duration: 1, bytes: 4)
    }
}

private actor ExportLog {
    private(set) var events: [String] = []
    func started(_ name: String) { events.append("start " + name) }
    func finished(_ name: String) { events.append("end " + name) }
}

@MainActor
struct ExportQueueTests {
    private func project() throws -> Project {
        var caption = Item(at: 0, duration: 30)
        caption["text"] = .string("Xin chào")
        let base = Project(name: "Queue")
        return try base.applying(.insert(track: base.requireTrack(role: TrackRole.captions).id, item: caption)).project
    }

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func request(_ name: String, in root: URL, srt: Bool = false, reserved: Set<URL> = []) throws
        -> ExportRequest
    {
        try ExportRequest(
            project: project(), root: root, workspace: nil, name: name, preset: .quickDraft,
            directory: root.appendingPathComponent("render"), includeSubRip: srt, normalizeAudio: false,
            reserved: reserved)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<400 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
        #expect(condition())
    }

    @Test("Exports run one at a time in request order and report progress as jobs")
    func sequentialQueue() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let log = ExportLog()
        let jobs = JobCenter()
        let queue = ExportQueue(jobs: jobs) { ExportPipeline(engine: FakeEngine(log: log), loudness: nil) }
        var finished: [String] = []
        let first = try queue.enqueue(try request("one", in: root, srt: true), author: .user) { result in
            if case .success(let outcome) = result { finished.append(outcome.receipt.url.lastPathComponent) }
        }
        let second = try queue.enqueue(try request("two", in: root), author: .agent) { result in
            if case .success(let outcome) = result { finished.append(outcome.receipt.url.lastPathComponent) }
        }
        #expect(jobs.job(first)?.state == .running)
        #expect(jobs.job(second)?.state == .queued)
        #expect(queue.queuedCount == 1)
        #expect(throws: ProjectError.self) { try queue.enqueue(try request("two", in: root), author: .user) { _ in } }

        try await waitUntil { finished.count == 2 }
        #expect(finished == ["one.mp4", "two.mp4"])
        #expect(await log.events == ["start one.mp4", "end one.mp4", "start two.mp4", "end two.mp4"])
        #expect(jobs.job(first)?.state == .completed)
        #expect(jobs.job(first)?.progress == 1)
        #expect(jobs.job(second)?.author == .agent)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("render/one.srt").path))
        #expect(!queue.isRunning)
        #expect(queue.reservedOutputs.isEmpty)
    }

    @Test("Cancelling a queued export skips it; cancelling the running one starts the next")
    func cancellation() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let log = ExportLog()
        let jobs = JobCenter()
        let queue = ExportQueue(jobs: jobs) { ExportPipeline(engine: FakeEngine(log: log, steps: 50), loudness: nil) }
        var results: [String: String] = [:]
        func track(_ name: String) -> @MainActor (Result<ExportOutcome, any Error>) -> Void {
            { result in
                switch result {
                case .success: results[name] = "done"
                case .failure(let error): results[name] = JobCenter.isCancellation(error) ? "cancelled" : "failed"
                }
            }
        }
        let first = try queue.enqueue(try request("a", in: root), author: .user, finished: track("a"))
        let second = try queue.enqueue(try request("b", in: root), author: .user, finished: track("b"))
        _ = try queue.enqueue(try request("c", in: root), author: .user, finished: track("c"))

        #expect(jobs.cancel(second))
        #expect(results["b"] == "cancelled")
        #expect(jobs.job(second)?.state == .cancelled)
        #expect(!jobs.cancel(second))
        try await waitUntil { jobs.job(first)?.progress ?? 0 > 0 }
        queue.cancelActive()
        try await waitUntil { results.count == 3 }
        #expect(results == ["a": "cancelled", "b": "cancelled", "c": "done"])
        #expect(jobs.job(first)?.state == .cancelled)
        #expect(!(await log.events).contains("start b.mp4"))
    }

    @Test("Export requests validate names and refuse existing or reserved outputs")
    func requestValidation() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let valid = try request("clip", in: root, srt: true)
        #expect(valid.output.lastPathComponent == "clip.mp4")
        #expect(valid.subRip?.lastPathComponent == "clip.srt")
        #expect(valid.captionText?.contains("Xin chào") == true)
        #expect(throws: ProjectError.self) { try request("a/b", in: root) }
        #expect(throws: ProjectError.self) { try request("clip", in: root, reserved: valid.outputs) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("render"), withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("render/taken.mp4"))
        #expect(throws: ProjectError.self) { try request("taken", in: root) }
        #expect(throws: ProjectError.self) {
            try ExportRequest(
                project: Project(name: "Empty"), root: root, workspace: nil, name: "empty", preset: .quickDraft,
                directory: root, includeSubRip: false, normalizeAudio: false)
        }
    }

    @Test("The job center records results, failures and drops everything on cancelAll")
    func jobCenter() async throws {
        struct Failure: LocalizedError { var errorDescription: String? { "boom" } }
        let jobs = JobCenter(historyLimit: 2)
        var callbacks = 0
        let ok = jobs.start("beats.detect", author: .claude, work: { _ in .integer(7) }, finished: { _ in callbacks += 1 })
        let bad = jobs.start("voice.speak", author: .codex, work: { _ in throw Failure() }, finished: { _ in callbacks += 1 })
        try await waitUntil { callbacks == 2 }
        #expect(jobs.job(ok)?.state == .completed)
        #expect(jobs.job(ok)?.result == .integer(7))
        #expect(jobs.job(bad)?.state == .failed)
        #expect(jobs.job(bad)?.error == "boom")
        _ = jobs.start("captions.generate", author: .user, work: { _ in .null })
        try await waitUntil { jobs.jobs.allSatisfy { !$0.isActive } }
        #expect(jobs.jobs.count == 2)
        #expect(jobs.job(ok) == nil)

        let slow = jobs.start("captions.generate", author: .user, work: { _ in
            try await Task.sleep(for: .seconds(5))
            return .null
        }, finished: { _ in callbacks += 1 })
        #expect(jobs.job(slow)?.state == .running)
        jobs.cancelAll()
        #expect(jobs.jobs.isEmpty)
        try await Task.sleep(for: .milliseconds(50))
        #expect(callbacks == 2)
    }
}
