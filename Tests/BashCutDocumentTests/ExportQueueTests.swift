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
    /// Exports to a file with this name fail instead of writing it.
    var failing: String?

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
        if url.lastPathComponent == failing { throw ProjectError.invalid("Render failed at project frame 20") }
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

    /// Polls for up to 30 s (a loaded machine runs the fake exports late), returning as soon as `condition` holds.
    private func waitUntil(
        _ condition: @MainActor () -> Bool, sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(30)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(condition(), sourceLocation: sourceLocation)
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

    @Test("A 720p draft of a 1080p edit scales picture offsets, so a corner picture-in-picture stays in frame")
    func draftScalesOffsets() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        var item = Item(id: "pip", at: 0, duration: 30)
        item["text"] = .string("Góc phải")
        item["transform"] = .object(["pan": .integer(763), "tilt": .integer(-243), "zoom": .number(0.55)])
        item["keyframes"] = .object(["pan": .array([.object(["frame": .integer(0), "value": .integer(763)])])])
        let base = Project(name: "PiP")
        let edit = try base.applying(.setFormat(width: 1920, height: 1080)).project
        let source = try edit.applying(.insert(track: edit.requireTrack(role: TrackRole.captions).id, item: item)).project
        let draft = try ExportRequest(
            project: source, root: root, workspace: nil, name: "draft", preset: .quickDraft, directory: root,
            includeSubRip: false, normalizeAudio: false)
        #expect(draft.project.width == 1280 && draft.project.height == 720)
        let placed = try #require(draft.project.tracks.flatMap(\.items).first { $0.id == "pip" })
        #expect(placed["transform"]?.object["pan"]?.double == 509)
        #expect(placed["transform"]?.object["tilt"]?.double == -162)
        #expect(placed["keyframes"]?.object["pan"]?.array.first?.object["value"]?.double == 509)
        // The edit itself keeps its 1080p offsets.
        #expect(draft.source.tracks.flatMap(\.items).first { $0.id == "pip" }?["transform"]?.object["pan"]?.double == 763)
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
        // Overwrite (#507-23): files on disk no longer count, a queued export still does.
        #expect(ExportRequest.availableName(
            "long1", preset: .quickDraft, directory: render, includeSubRip: false, ignoringFiles: true) == "long1")
        #expect(ExportRequest.availableName(
            "queued", preset: .quickDraft, directory: render, includeSubRip: false,
            reserved: [render.appendingPathComponent("queued.mp4")], ignoringFiles: true) == "queued-2")
        try Data().write(to: render.appendingPathComponent("long1.vtt"))
        #expect(ExportRequest.existingOutputs("long1", preset: .quickDraft, directory: render).map(\.lastPathComponent)
            == ["long1.mp4", "long1.vtt"])
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

    @Test("The report's speech coverage and the credits come with the export, made off the main actor (#350)")
    func outcomeCarriesReportFacts() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        var project = try project()
        project["review"] = .object(["credits": .bool(true)])
        let request = try ExportRequest(
            project: project, root: root, workspace: nil, name: "facts", preset: .quickDraft,
            directory: root.appendingPathComponent("render"), includeSubRip: false, normalizeAudio: false, reserved: [])
        let pipeline = ExportPipeline(engine: FakeEngine(log: ExportLog()), loudness: nil)
        let outcome = try await pipeline.run(request) { _, _ in }
        #expect(outcome.speechCoverage == TimelineReview.speechCoverage(request.source, transcripts: request.transcripts))
        #expect(outcome.credits == ProjectCredits.of(project).json)
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

    @Test("A failed export shows as failed in export.status with its error until a later export finishes")
    func controllerFailure() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let log = ExportLog()
        let exports = ExportController(jobs: JobCenter()) {
            ExportPipeline(engine: FakeEngine(log: log, failing: "bad.mp4"), loudness: nil)
        }
        var finished = 0
        try exports.enqueue(try request("one", in: root), author: .agent) { _ in finished += 1 }
        try await waitUntil { finished == 1 }
        try exports.enqueue(try request("bad", in: root), author: .agent) { _ in finished += 1 }
        try await waitUntil { finished == 2 }
        var status = exports.statusJSON.object
        #expect(status["state"] == .string("failed"))
        #expect(status["error"]?.string?.contains("project frame 20") == true)
        #expect(status["path"] == .string(root.appendingPathComponent("render/bad.mp4").path))
        #expect(status["lastExport"]?.object["path"] == .string(root.appendingPathComponent("render/one.mp4").path))
        try exports.enqueue(try request("two", in: root), author: .agent) { _ in finished += 1 }
        try await waitUntil { finished == 3 }
        status = exports.statusJSON.object
        #expect(status["state"] == .string("completed"))
        #expect(status["error"] == nil)
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

/// Several outputs in one request (#593).
extension ExportQueueTests {
    @Test("Several outputs queue one export each, named name-<preset>, and all land in the export history")
    func severalOutputs() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let render = root.appendingPathComponent("render")
        let presets: [ExportPreset] = [.tiktok, .shorts]
        #expect(ExportRequest.outputName("trip", preset: .tiktok, among: [.tiktok]) == "trip")
        #expect(presets.map { ExportRequest.outputName("trip", preset: $0, among: presets) } == ["trip-tiktok", "trip-shorts"])
        let base = ExportRequest.availableName("trip", presets: presets, directory: render, includeSubRip: false)
        #expect(base == "trip")

        let log = ExportLog()
        let exports = ExportController(jobs: JobCenter()) { ExportPipeline(engine: FakeEngine(log: log), loudness: nil) }
        var finished: [String] = []
        for preset in presets {
            let request = try ExportRequest(
                project: project(), root: root, workspace: nil,
                name: ExportRequest.outputName(base, preset: preset, among: presets), preset: preset,
                directory: render, includeSubRip: false, normalizeAudio: false, reserved: exports.queue.reservedOutputs)
            try exports.enqueue(request, author: .user) { result in
                if case .success(let outcome) = result { finished.append(outcome.receipt.url.lastPathComponent) }
            }
        }
        #expect(exports.queue.active.count == 2)
        // The second name is taken while the first is queued, so the suggestion moves both on.
        #expect(ExportRequest.availableName(
            "trip", presets: presets, directory: render, includeSubRip: false,
            reserved: exports.queue.reservedOutputs) == "trip-2")
        try await waitUntil { finished.count == 2 }
        #expect(finished == ["trip-tiktok.mp4", "trip-shorts.mp4"])
        let history = try exports.ledger.all(projectRoot: root)
        #expect(history.map(\.preset) == ["tiktok", "shorts"])
        #expect(history.map { URL(fileURLWithPath: $0.path).lastPathComponent } == ["trip-tiktok.mp4", "trip-shorts.mp4"])
        // On disk now: the next export of both outputs gets a fresh name for both.
        #expect(ExportRequest.availableName("trip", presets: presets, directory: render, includeSubRip: false) == "trip-2")
    }
}
