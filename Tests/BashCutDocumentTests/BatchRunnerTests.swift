import AVFoundation
import BashCutAutomation
import BashCutDocument
import BashCutEngine
import BashCutProject
import BashCutStorage
import BashCutTestSupport
import Foundation
import Testing

/// Stands in for a captions.transcribe plugin: the words come from the file name, after a short wait.
private enum TestCaptionsProvider {
    static func transcribe(_ media: Media, delay: Duration) async throws -> String {
        try await Task.sleep(for: delay)
        return "Hello from " + URL(fileURLWithPath: media.path).deletingPathExtension().lastPathComponent
    }
}

/// An editor with one open project, whose commands go through a real `CommandRegistry` (spec validation, tokens,
/// the project-switch gate) like the app's: project create/open/format/save write real project folders, media import
/// adds and places the file, captions generate runs as a job with the test provider, and exports render with the
/// AVFoundation engine.
@MainActor
private final class TestBatchHost: BatchHost {
    let jobs = JobCenter()
    let registry = CommandRegistry()
    let defaultProjectsFolder: URL
    private let storage = ProjectStorage()
    private let token: String
    private var history: ProjectHistory?
    private var url: URL?
    private var disk: Data?
    private(set) var finished: [BatchRunStatus] = []
    /// File names whose captions fail, to test onFailure.
    var failingCaptions: Set<String> = []
    var captionsDelay = Duration.milliseconds(20)
    private lazy var exports = ExportQueue(jobs: jobs) {
        ExportPipeline(engine: AVFoundationRenderEngine(), loudness: nil)
    }

    init(projects: URL) {
        defaultProjectsFolder = projects
        token = registry.issueToken(author: .agent)
        registerProjectCommands()
        registerEditCommands()
    }

    var openProjectFile: URL? { url }
    var projectRevision: Int? { history?.project.revision }
    var firstMediaID: String? { history?.project.media.first?.id }

    func invoke(_ method: String, _ params: [String: JSONValue]) async throws -> JSONValue {
        let response = await registry.handle(RPCRequest(method: method, params: params, token: token))
        if let error = response.error { throw error }
        return response.result ?? .null
    }

    func isPluginAction(_ id: String) -> Bool { false }

    func startBatchExport(preset: String, name: String, options: [String: JSONValue], replacing: Bool) throws
        -> (job: String, file: URL)
    {
        guard let project = history?.project, let root = url?.deletingLastPathComponent(),
            let preset = ExportPreset(argument: preset)
        else { throw ProjectError.invalid("No project or preset") }
        let request = try ExportRequest(
            project: project, root: root, workspace: nil, name: name, preset: preset,
            directory: root.appendingPathComponent("render"), includeSubRip: options["includeSRT"]?.bool ?? false,
            normalizeAudio: false, reserved: exports.reservedOutputs)
        return (try exports.enqueue(request, author: .agent) { _ in }, request.output)
    }

    /// The token stays: these tests run several batches on one host (the app makes a host per run).
    func runFinished(_ run: BatchRunStatus) { finished.append(run) }

    private func open(_ load: (history: ProjectHistory, url: URL, disk: Data)) {
        jobs.cancelAll() // as the document's reset does on every project switch
        (history, url, disk) = (load.history, load.url, load.disk)
    }

    private func commit(_ operation: EditOperation) throws {
        guard var history else { throw ProjectError.invalid("No project open") }
        try history.apply(operation, label: "Batch test", author: .agent)
        self.history = history
    }

    private func registerProjectCommands() {
        registry.register("project.create") { [unowned self] arguments, _ in
            var setup = ProjectSetup()
            setup.name = try arguments.string("name")
            setup.canvas = ProjectSetup.Canvas(rawValue: try arguments.string("canvas")) ?? .portrait
            let footage = URL(fileURLWithPath: try arguments.string("footage")).deletingLastPathComponent()
            let created = try await storage.create(
                setup, in: URL(fileURLWithPath: try arguments.string("directory")), footage: footage)
            open((ProjectHistory(project: created.project), created.url, created.diskData))
            return .object(["project": .string(created.url.path)])
        }
        registry.register("project.open") { [unowned self] arguments, _ in
            guard let file = ProjectStorage.projectFile(for: URL(fileURLWithPath: try arguments.string("path"))) else {
                throw RPCFailure(-32602, "No project")
            }
            let loaded = try await storage.load(file)
            open((loaded.history, file, loaded.diskData))
            return .object(["project": .string(file.path)])
        }
        registry.register("project.format") { [unowned self] arguments, _ in
            let outputs = try arguments.string("outputs").split(separator: ",").map { JSONValue.string(String($0)) }
            try commit(.setProjectProperties(patch: ["output": .object(["presets": .array(outputs)])]))
            return .object(["rev": .integer(projectRevision ?? 0)])
        }
        registry.register("project.save") { [unowned self] _, _ in
            guard let history, let url else { throw ProjectError.invalid("No project open") }
            disk = try await storage.save(history, to: url, expectedDisk: disk)
            return .object(["project": .string(url.path)])
        }
    }

    private func registerEditCommands() {
        registry.register("media.import") { [unowned self] arguments, _ in
            // As the app stores a file in the linked footage folder.
            let path = "footage/" + URL(fileURLWithPath: try arguments.string("path")).lastPathComponent
            let media = Media(fields: [
                "id": .string(UUID().uuidString), "path": .string(path), "kind": .string("video"),
                "fps": FrameRate().json, "frames": .integer(59), "hasAudio": .bool(true),
            ])
            try commit(.addMedia(media))
            if arguments.bool("place"), let main = history?.project.tracks.first(where: { $0["role"]?.string == TrackRole.main }) {
                try commit(.insert(track: main.id, item: Item(id: UUID().uuidString, media: media.id, at: 0, duration: 59)))
            }
            return .object(["media": .string(media.id), "existing": .bool(false)])
        }
        registry.register("captions.generate") { [unowned self] arguments, author in
            let id = try arguments.string("media")
            guard let media = history?.project.media.first(where: { $0.id == id }) else {
                throw RPCFailure(-32602, "No media \(id)")
            }
            let job = jobs.start("captions.generate", author: author ?? .agent) { [unowned self] _ in
                if failingCaptions.contains(media.fileName) {
                    throw RPCFailure(-32000, "No captions.transcribe provider", category: .capabilityMissing)
                }
                var caption = Item(at: 0, duration: 59)
                caption["text"] = .string(try await TestCaptionsProvider.transcribe(media, delay: captionsDelay))
                guard let track = history?.project.tracks.first(where: { $0["role"]?.string == TrackRole.captions }) else {
                    throw ProjectError.invalid("No captions layer")
                }
                try commit(.insert(track: track.id, item: caption))
                return .object(["captions": .integer(1), "provider": .string("test")])
            }
            return .object(["job": .string(job)])
        }
    }
}

@MainActor
struct BatchRunnerTests {
    /// Three generated clips with different names, in their own footage folder.
    private func clips(in root: URL) async throws -> [URL] {
        let footage = root.appendingPathComponent("footage", isDirectory: true)
        try FileManager.default.createDirectory(at: footage, withIntermediateDirectories: true)
        let video = try await TestFixtures.requireVideo()
        return try (1...3).map { number in
            let url = footage.appendingPathComponent("clip-\(number).mp4")
            try FileManager.default.copyItem(at: video, to: url)
            return url
        }
    }

    private func pipeline(inputs: [BatchInput], projects: URL, onFailure: BatchFailurePolicy = .skipItem) -> BatchPipeline {
        BatchPipeline(
            name: "Captions draft", inputs: inputs, template: BatchTemplate(canvas: "landscape", outputs: ["quick-draft"]),
            steps: [
                BatchStep("media.import", params: ["path": .string("{input}"), "place": .bool(true)], label: "Import"),
                BatchStep("captions.generate", params: ["media": .string("{media}")], label: "Auto captions"),
                BatchStep(BatchRunner.exportAction, label: "Export"),
            ],
            onFailure: onFailure, projectsFolder: projects.path)
    }

    private func waitUntilFinished(_ runner: BatchRunner, _ id: String) async throws -> BatchRunStatus {
        let deadline = ContinuousClock.now + .seconds(120)
        while runner.run(id)?.state.isFinished != true, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        return try #require(runner.run(id))
    }

    @Test("Import, test-provider captions and export over 3 generated clips make 3 projects and 3 files")
    func threeClips() async throws {
        let root = try TestFixtures.temporaryDirectory("batch-run")
        defer { try? FileManager.default.removeItem(at: root) }
        let projects = root.appendingPathComponent("projects", isDirectory: true)
        let clips = try await clips(in: root)
        let host = TestBatchHost(projects: projects)
        let pipeline = pipeline(inputs: [BatchInput(path: clips[0].deletingLastPathComponent().path)], projects: projects)
        try BatchRunner.check(pipeline) { _ in false }
        let items = try pipeline.items()
        #expect(items.map(\.name) == ["clip-1", "clip-2", "clip-3"])

        let runner = BatchRunner()
        let id = runner.add(pipeline, items: items, awaitingApproval: false)
        runner.start(id, host: host, author: .agent)
        let run = try await waitUntilFinished(runner, id)

        #expect(run.state == .completed)
        #expect(run.items.compactMap(\.error).isEmpty, "\(run.items.compactMap(\.error))")
        #expect(run.count(.completed) == 3)
        #expect(host.finished.map(\.id) == [id])
        let files = run.items.flatMap(\.outputs)
        #expect(files.map { URL(fileURLWithPath: $0).lastPathComponent }
            == ["clip-1-quick-draft.mp4", "clip-2-quick-draft.mp4", "clip-3-quick-draft.mp4"])
        for (item, clip) in zip(run.items, clips) {
            #expect(item.steps.map(\.state) == [.completed, .completed, .completed])
            #expect(item.steps.allSatisfy { $0.job != nil })
            let file = try #require(item.project)
            let saved = try Project.decode(Data(contentsOf: file))
            #expect(saved.outputPresets == ["quick-draft"])
            #expect(saved.media.map(\.path) == ["footage/" + clip.lastPathComponent])
            let captions = saved.tracks.first { $0["role"]?.string == TrackRole.captions }?.items ?? []
            #expect(captions.map { $0["text"]?.string } == ["Hello from \(clip.deletingPathExtension().lastPathComponent)"])
            let output = try #require(item.outputs.first)
            #expect(output.hasPrefix(file.deletingLastPathComponent().appendingPathComponent("render").path))
            #expect(try await AVURLAsset(url: URL(fileURLWithPath: output)).loadTracks(withMediaType: .video).count == 1)
        }
        let made = try FileManager.default.contentsOfDirectory(atPath: projects.path).sorted()
        #expect(made == ["clip-1", "clip-2", "clip-3"])
    }

    @Test("A failed step skips the rest of its item; onFailure stop ends the batch; a project input reruns in place")
    func failures() async throws {
        let root = try TestFixtures.temporaryDirectory("batch-failure")
        defer { try? FileManager.default.removeItem(at: root) }
        let projects = root.appendingPathComponent("projects", isDirectory: true)
        let clips = try await clips(in: root)
        let host = TestBatchHost(projects: projects)
        host.failingCaptions = [clips[1].lastPathComponent]
        let runner = BatchRunner()

        let skipping = pipeline(inputs: clips.map { BatchInput(path: $0.path) }, projects: projects)
        let first = runner.add(skipping, items: try skipping.items(), awaitingApproval: false)
        runner.start(first, host: host, author: .agent)
        let skipped = try await waitUntilFinished(runner, first)
        #expect(skipped.state == .completed)
        #expect(skipped.items.map(\.state) == [.completed, .failed, .completed])
        #expect(skipped.items[1].steps.map(\.state) == [.completed, .failed, .skipped])
        #expect(skipped.items[1].steps[1].errorCategory == "capability_missing")
        #expect(skipped.items[1].project != nil, "the failed item's project stays, to open and fix")

        // The same names again: new projects get free folder names; stop ends the batch at the failed item.
        let stopping = pipeline(inputs: clips.map { BatchInput(path: $0.path) }, projects: projects, onFailure: .stop)
        let second = runner.add(stopping, items: try stopping.items(), awaitingApproval: false)
        runner.start(second, host: host, author: .agent)
        let stopped = try await waitUntilFinished(runner, second)
        #expect(stopped.state == .failed)
        #expect(stopped.items.map(\.state) == [.completed, .failed, .skipped])
        #expect(stopped.items[0].project?.deletingLastPathComponent().lastPathComponent == "clip-1-2")

        // A project input is that project: its steps run on it, no new folder is made.
        let existing = try #require(skipped.items[0].project)
        var rerun = BatchPipeline(inputs: [BatchInput(path: existing.deletingLastPathComponent().path)],
                                  steps: [BatchStep(BatchRunner.exportAction, params: ["presets": .string("quick-draft")])])
        rerun.outputName = "{name}-again"
        let third = runner.add(rerun, items: try rerun.items(), awaitingApproval: false)
        runner.start(third, host: host, author: .agent)
        let reran = try await waitUntilFinished(runner, third)
        #expect(reran.state == .completed)
        #expect(reran.items.first?.project == existing)
        #expect(reran.items.first?.outputs.first.map { URL(fileURLWithPath: $0).lastPathComponent } == "clip-1-again.mp4")
    }

    @Test("Cancelling a running batch cancels its running step's job and the items after it")
    func cancelRunning() async throws {
        let root = try TestFixtures.temporaryDirectory("batch-cancel")
        defer { try? FileManager.default.removeItem(at: root) }
        let projects = root.appendingPathComponent("projects", isDirectory: true)
        let clips = try await clips(in: root)
        let host = TestBatchHost(projects: projects)
        host.captionsDelay = .seconds(30)
        let runner = BatchRunner()
        let pipeline = pipeline(inputs: clips.map { BatchInput(path: $0.path) }, projects: projects)
        let id = runner.add(pipeline, items: try pipeline.items(), awaitingApproval: false)
        runner.start(id, host: host, author: .agent)
        let deadline = ContinuousClock.now + .seconds(30)
        while runner.run(id)?.items[0].steps[1].job == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let job = try #require(runner.run(id)?.items[0].steps[1].job)
        #expect(runner.cancel(id, jobs: host.jobs))
        let run = try await waitUntilFinished(runner, id)
        #expect(run.state == .cancelled)
        #expect(run.items.map(\.state) == [.cancelled, .cancelled, .cancelled])
        #expect(run.items[0].steps.map(\.state) == [.completed, .cancelled, .cancelled])
        #expect(host.jobs.job(job)?.state == .cancelled)
        #expect(host.finished.map(\.state) == [.cancelled])
    }

    @Test("Steps that need approval, open projects or do not exist are refused before anything runs")
    func refusedSteps() throws {
        func check(_ action: String, params: [String: JSONValue] = [:]) -> String? {
            let pipeline = BatchPipeline(inputs: [BatchInput(path: "/tmp")], steps: [BatchStep(action, params: params)])
            do { try BatchRunner.check(pipeline) { $0 == "bashcut.example/run" } } catch { return error.localizedDescription }
            return nil
        }
        #expect(check("export.start")?.contains("use the export step") == true)
        #expect(check("export.otio")?.contains("approval") == true)
        #expect(check("project.open")?.contains("opens each item's project") == true)
        #expect(check("batch.run")?.contains("approval") == true)
        #expect(check("batch.cancel")?.contains("cannot run in a batch") == true)
        #expect(check("captions.typo")?.contains("no command or installed plugin action") == true)
        #expect(check("export")?.contains("presets") == true)
        #expect(check("export", params: ["presets": .array([.string("tiktok")])]) == nil)
        #expect(check("export", params: ["presets": .string("tiktok,vimeo")])?.contains("unknown export preset vimeo") == true)
        #expect(check("bashcut.example/run") == nil)
        #expect(check("captions.generate") == nil)
        #expect(check("timeline.apply") == nil)
    }

    @Test("Cancelling a waiting run or one awaiting approval ends it without running; denial marks it denied")
    func cancelAndDeny() throws {
        let runner = BatchRunner()
        let source = BatchItemSource(name: "a", url: URL(fileURLWithPath: "/tmp/a.mp4"), kind: .file)
        let pipeline = BatchPipeline(inputs: [BatchInput(path: "/tmp/a.mp4")], steps: [BatchStep("project.save")])
        let waiting = runner.add(pipeline, items: [source], awaitingApproval: true)
        #expect(runner.active?.id == waiting)
        #expect(runner.cancel(waiting))
        #expect(runner.run(waiting)?.state == .cancelled)
        #expect(runner.run(waiting)?.items.first?.state == .cancelled)
        #expect(!runner.cancel(waiting))
        let denied = runner.add(pipeline, items: [source], awaitingApproval: true)
        runner.deny(denied)
        #expect(runner.run(denied)?.state == .denied)
        #expect(runner.active == nil)
        let status = runner.run(denied)?.json(full: false).object
        #expect(status?["counts"]?.object["skipped"] == .integer(1))
        #expect(status?["concurrency"]?.object["used"] == .integer(1))
    }

    @Test("Retry runs only the failed item, in the project it made, from the step that failed")
    func retryFromFailedStep() async throws {
        let root = try TestFixtures.temporaryDirectory("batch-retry")
        defer { try? FileManager.default.removeItem(at: root) }
        let projects = root.appendingPathComponent("projects", isDirectory: true)
        let clips = try await clips(in: root)
        let host = TestBatchHost(projects: projects)
        host.failingCaptions = [clips[1].lastPathComponent]
        let runner = BatchRunner()
        let pipeline = pipeline(inputs: clips.map { BatchInput(path: $0.path) }, projects: projects)
        let id = runner.add(pipeline, items: try pipeline.items(), awaitingApproval: false)
        runner.start(id, host: host, author: .agent)
        let first = try await waitUntilFinished(runner, id)
        #expect(first.items.map(\.state) == [.completed, .failed, .completed])
        #expect(first.retryableItems == [1])
        let made = try #require(first.items[1].project)
        let importJob = first.items[1].steps[0].job

        host.failingCaptions = []
        #expect(runner.retry(id, host: host, author: .agent))
        let second = try await waitUntilFinished(runner, id)
        #expect(second.state == .completed)
        #expect(second.items.map(\.state) == [.completed, .completed, .completed])
        #expect(second.retryableItems.isEmpty)
        #expect(second.items[1].project == made, "the retry reopens the project it made")
        #expect(second.items[1].steps.map(\.state) == [.completed, .completed, .completed])
        #expect(second.items[1].steps[0].job == importJob, "the import that completed does not run again")
        #expect(second.items[0].steps == first.items[0].steps, "items that completed are left alone")
        let saved = try Project.decode(Data(contentsOf: made))
        #expect(saved.media.count == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: projects.path).sorted() == ["clip-1", "clip-2", "clip-3"])
        #expect(!runner.retry(id, host: host, author: .agent), "nothing left to retry")
    }

    @Test("Runs are saved; one that was running comes back interrupted, and retry goes on from where it stopped")
    func savedRunsComeBackInterrupted() async throws {
        let root = try TestFixtures.temporaryDirectory("batch-store")
        defer { try? FileManager.default.removeItem(at: root) }
        let projects = root.appendingPathComponent("projects", isDirectory: true)
        let clips = try await clips(in: root)
        let store = BatchRunStore(file: root.appendingPathComponent("Runs.json"))
        let host = TestBatchHost(projects: projects)
        host.captionsDelay = .seconds(30)
        let runner = BatchRunner(store: store)
        let pipeline = pipeline(inputs: clips.map { BatchInput(path: $0.path) }, projects: projects)
        let id = runner.add(pipeline, items: try pipeline.items(), awaitingApproval: false)
        runner.start(id, host: host, author: .agent)
        let deadline = ContinuousClock.now + .seconds(30)
        while runner.run(id)?.items[0].steps[1].job == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        // As a quit does: saved at once, interrupted.
        runner.interrupt(jobs: host.jobs)
        #expect(runner.run(id)?.state == .interrupted)
        // The app quits here; the test waits for the stopped run to let go of the host before the next one uses it.
        let stopped = ContinuousClock.now + .seconds(30)
        while host.finished.isEmpty, ContinuousClock.now < stopped { try await Task.sleep(for: .milliseconds(20)) }
        #expect(host.finished.map(\.state) == [.interrupted])

        let restored = BatchRunner(store: store)
        let run = try #require(restored.run(id))
        #expect(run.state == .interrupted)
        #expect(run.pipeline == pipeline)
        #expect(run.items[0].steps.allSatisfy { $0.state == .waiting }, "the unsaved steps of the item run again")
        #expect(run.items[0].project != nil)
        #expect(run.items[1...].allSatisfy { $0.state == .waiting })
        #expect(run.retryableItems == [0, 1, 2])

        host.captionsDelay = .milliseconds(20)
        #expect(restored.retry(id, host: host, author: .agent))
        let resumed = try await waitUntilFinished(restored, id)
        #expect(resumed.state == .completed)
        #expect(resumed.items.map(\.state) == [.completed, .completed, .completed], "\(resumed.items.map(\.error))")
        #expect(resumed.items[0].project == run.items[0].project)
        let saved = try Project.decode(Data(contentsOf: try #require(resumed.items[0].project)))
        #expect(saved.media.count == 1, "the interrupted import was not saved, so it is not there twice")
        #expect(BatchRunStore(file: store.file).load().first?.state == .completed)
    }
}
