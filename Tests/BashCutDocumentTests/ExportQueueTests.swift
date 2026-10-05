import AVFoundation
import BashCutDocument
import BashCutEngine
import BashCutInterchange
import BashCutProject
import Foundation
import Testing

/// Renders nothing: each export waits `steps` short sleeps (cancellable), then writes a stub file.
private struct FakeEngine: RenderEngine {
    let log: ExportLog
    var steps = 3

    func build(_ project: Project, root: URL, workspace: URL?, purpose: RenderPurpose) async throws
        -> CompositionSnapshot
    {
        CompositionSnapshot(
            composition: AVMutableComposition(), videoComposition: AVMutableVideoComposition(),
            audioMix: AVMutableAudioMix())
    }

    func exportAudio(_ snapshot: CompositionSnapshot, to url: URL,
                     progress: @escaping @Sendable (Double) -> Void) async throws -> ExportReceipt {
        throw ProjectError.invalid("Unexpected audio measurement export in this test")
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
    private func project(captionText: String = "Xin chào") throws -> Project {
        var caption = Item(at: 0, duration: 30)
        caption["text"] = .string(captionText)
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
        let silent = try ExportRequest(
            project: project(captionText: " "), root: root, workspace: nil,
            name: "silent", preset: .quickDraft, directory: root, includeSubRip: true, normalizeAudio: false)
        #expect(silent.subRip == nil)
        #expect(!silent.includesSubRip)
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

    @Test("A taken export name gets the next free number, and the error suggests it")
    func availableNames() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let render = root.appendingPathComponent("render")
        try FileManager.default.createDirectory(at: render, withIntermediateDirectories: true)
        func free(_ name: String, srt: Bool = false, reserved: Set<URL> = []) -> String {
            ExportRequest.availableName(name, preset: .quickDraft, directory: render, includeSubRip: srt, reserved: reserved)
        }
        #expect(free("long1") == "long1")
        try Data().write(to: render.appendingPathComponent("long1.mp4"))
        #expect(ExportRequest.nameIsTaken("long1", preset: .quickDraft, directory: render, includeSubRip: false))
        #expect(!ExportRequest.nameIsTaken("long1", preset: .proRes422HQ, directory: render, includeSubRip: false))
        #expect(free("long1") == "long1-2")
        try Data().write(to: render.appendingPathComponent("long1-2.mp4"))
        #expect(free("long1") == "long1-3")
        #expect(free("long1-2") == "long1-3")
        try Data().write(to: render.appendingPathComponent("trip-2026.mp4"))
        #expect(free("trip-2026") == "trip-2026-2")
        try Data().write(to: render.appendingPathComponent("clip.srt"))
        #expect(free("clip") == "clip")
        #expect(free("clip", srt: true) == "clip-2")
        #expect(free("queued", reserved: [render.appendingPathComponent("queued.mp4")]) == "queued-2")
        do {
            _ = try request("long1", in: root)
            Issue.record("Expected a taken name to fail")
        } catch {
            #expect(error.localizedDescription.contains("long1-3"))
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

    @Test("The controller keeps the last report in the project history and describes it in export.status")
    func controllerReports() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let log = ExportLog()
        let exports = ExportController(jobs: JobCenter()) { ExportPipeline(engine: FakeEngine(log: log), loudness: nil) }
        #expect(exports.statusJSON.object["state"] == .string("idle"))
        var finished = 0
        try exports.enqueue(try request("one", in: root), author: .user) { _ in finished += 1 }
        #expect(exports.statusJSON.object["state"] == .string("running"))
        try await waitUntil { finished == 1 }
        #expect(exports.report?.receipt.url.lastPathComponent == "one.mp4")
        #expect(exports.report?.captionCount == 1)
        #expect(exports.report?.comparison == nil)
        try exports.enqueue(try request("two", in: root), author: .agent) { _ in finished += 1 }
        try await waitUntil { finished == 2 }
        #expect(exports.report?.comparison != nil)
        let status = exports.statusJSON.object
        #expect(status["state"] == .string("completed"))
        #expect(status["path"] == .string(root.appendingPathComponent("render/two.mp4").path))

        let reopened = ExportController(jobs: JobCenter()) { ExportPipeline(engine: FakeEngine(log: log), loudness: nil) }
        reopened.restoreReport(projectRoot: root)
        #expect(reopened.report?.receipt.url.lastPathComponent == "two.mp4")
        reopened.reset()
        #expect(reopened.report == nil)
    }

    @Test("The export toast shows the newest notice until dismissed; failures stay and a project switch clears it")
    func controllerNotice() {
        let log = ExportLog()
        let exports = ExportController(jobs: JobCenter()) { ExportPipeline(engine: FakeEngine(log: log), loudness: nil) }
        #expect(exports.notice == nil)
        exports.post(ExportNotice(.started, name: "one.mp4", author: .claude))
        #expect(exports.notice?.kind == .started)
        #expect(exports.notice?.author == .claude)
        exports.post(ExportNotice(.failed("Disk full"), name: "one.mp4", author: .claude))
        #expect(exports.notice?.kind == .failed("Disk full"))
        exports.dismissNotice()
        #expect(exports.notice == nil)
        exports.post(ExportNotice(.finished, name: "two.mp4", author: .user))
        exports.reset()
        #expect(exports.notice == nil)
    }

    @Test("OTIO exports refuse to replace a file unless asked")
    func otioReplace() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("render/cut.otio")
        try TimelineFormats.write(try project(), with: OpenTimelineIOExporter(), to: url)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(throws: ProjectError.self) { try TimelineFormats.write(try project(), with: OpenTimelineIOExporter(), to: url) }
        try TimelineFormats.write(try project(), with: OpenTimelineIOExporter(), to: url, allowReplace: true)
    }
}

@Suite("Timeline format registry")
struct TimelineFormatsTests {
    @Test("Format IDs are unique and found by ID")
    func registry() {
        let exporters = TimelineFormats.exporters.map(\.id)
        let importers = TimelineFormats.importers.map(\.id)
        #expect(Set(exporters).count == exporters.count)
        #expect(Set(importers).count == importers.count)
        #expect(TimelineFormats.exporter("otio")?.fileExtension == "otio")
        #expect(TimelineFormats.exporter("srt")?.fileExtension == "srt")
        #expect(TimelineFormats.importer("legacy-edl")?.fileExtensions == ["json"])
        #expect(TimelineFormats.exporter("fcpxml") == nil)
    }
}
