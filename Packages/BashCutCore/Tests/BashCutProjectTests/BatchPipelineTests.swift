import BashCutProject
import Foundation
import Testing

struct BatchPipelineTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("batch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func decode(_ text: String) throws -> BatchPipeline {
        try JSONDecoder().decode(BatchPipeline.self, from: Data(text.utf8))
    }

    @Test("A pipeline reads paths or {path, kind} inputs, defaults and keeps unknown fields at every level")
    func roundTrip() throws {
        let pipeline = try decode("""
            {"name": "Vietsub", "inputs": ["/a.mp4", {"path": "/p", "kind": "project", "note": 1}],
             "template": {"canvas": "portrait", "fps": 30, "outputs": "tiktok, shorts", "look": "warm"},
             "steps": [{"action": "media.import", "params": {"path": "{input}"}, "retry": 2},
                       {"action": "export"}],
             "future": true}
            """)
        #expect(pipeline.inputs == [BatchInput(path: "/a.mp4"), {
            var input = BatchInput(path: "/p", kind: .project)
            input.extra = ["note": .integer(1)]
            return input
        }()])
        #expect(pipeline.template.fps == "30")
        #expect(pipeline.template.outputs == ["tiktok", "shorts"])
        #expect(pipeline.template.createParameters == ["canvas": .string("portrait"), "fps": .string("30")])
        #expect(pipeline.onFailure == .skipItem)
        #expect(pipeline.concurrency == 1)
        #expect(pipeline.outputName == "{name}-{preset}")
        #expect(pipeline.steps[1].params.isEmpty)
        let again = try JSONDecoder().decode(BatchPipeline.self, from: JSONEncoder().encode(pipeline))
        #expect(again == pipeline)
        let json = pipeline.json.object
        #expect(json["future"] == .bool(true))
        #expect(json["template"]?.object["look"] == .string("warm"))
        #expect(json["steps"]?.array.first?.object["retry"] == .integer(2))
        #expect(json["version"] == .integer(1))
        try pipeline.validate()
    }

    @Test("Bad pipelines name what is wrong")
    func invalid() throws {
        func message(_ text: String) -> String? {
            do { try decode(text).validate() } catch { return error.localizedDescription }
            return nil
        }
        let steps = #""steps": [{"action": "project.save"}]"#
        #expect(message(#"{"inputs": [], \#(steps)}"#)?.contains("at least one input") == true)
        #expect(message(#"{"inputs": ["/a"], "steps": []}"#)?.contains("at least one step") == true)
        #expect(message(#"{"inputs": ["/a"], \#(steps), "concurrency": 9}"#)?.contains("1…8") == true)
        #expect(message(#"{"inputs": ["/a"], \#(steps), "onFailure": "retry"}"#)?.contains("skip or stop") == true)
        #expect(message(#"{"inputs": ["/a"], \#(steps), "outputName": "{preset}"}"#)?.contains("{name} or {index}") == true)
        #expect(message(#"{"inputs": ["/a"], \#(steps), "outputName": "{name}-{lang}"}"#)?.contains("{lang}") == true)
        #expect(message(#"{"inputs": ["/a"], "steps": [{"params": {}}]}"#)?.contains("steps[0]") == true)
        #expect(message(#"{"version": 2, "inputs": ["/a"], \#(steps)}"#)?.contains("version 2") == true)
        #expect(message(#"{"inputs": [{"path": "/a", "kind": "url"}], \#(steps)}"#)?.contains("file, folder or project") == true)
    }

    @Test("Output names fill their tokens and lose characters a file name cannot hold")
    func outputNames() {
        var pipeline = BatchPipeline(name: "Vietsub", inputs: [], steps: [])
        #expect(pipeline.outputFileName(item: "interview-01", index: 0, preset: "tiktok") == "interview-01-tiktok")
        pipeline.outputName = "{index}. {name}/{pipeline}: {preset}"
        #expect(pipeline.outputFileName(item: "a", index: 2, preset: "shorts") == "3. a-Vietsub- shorts")
    }

    @Test("Step parameters get the item's variables, also nested; unknown ones stay")
    func variables() {
        let step = BatchStep("captions.generate", params: [
            "media": .string("{media}"), "list": .array([.string("{name}.srt")]), "deep": .object(["path": .string("{input}")]),
            "other": .string("{nope}"), "count": .integer(3),
        ])
        let resolved = step.resolvedParams(["media": "m1", "name": "clip", "input": "/f/clip.mp4"])
        #expect(resolved["media"] == .string("m1"))
        #expect(resolved["list"] == .array([.string("clip.srt")]))
        #expect(resolved["deep"] == .object(["path": .string("/f/clip.mp4")]))
        #expect(resolved["other"] == .string("{nope}"))
        #expect(resolved["count"] == .integer(3))
    }

    @Test("Inputs expand to items: files, a folder's media and project folders, projects; duplicates once")
    func items() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let shoot = root.appendingPathComponent("shoot", isDirectory: true)
        let project = shoot.appendingPathComponent("old-edit", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        for name in ["b.mov", "a.mp4", "notes.txt", "c.png"] {
            try Data().write(to: shoot.appendingPathComponent(name))
        }
        try Data("{}".utf8).write(to: project.appendingPathComponent("project.bashcut.json"))
        let pipeline = BatchPipeline(
            inputs: [BatchInput(path: "shoot"), BatchInput(path: "shoot/a.mp4"), BatchInput(path: project.path)],
            steps: [BatchStep("project.save")])
        let items = try pipeline.items(relativeTo: root)
        #expect(items.map(\.name) == ["a", "b", "c", "old-edit"])
        #expect(items.map(\.kind) == [.file, .file, .file, .project])
        #expect(items.last?.url.lastPathComponent == "project.bashcut.json")

        #expect(throws: ProjectError.self) {
            try BatchPipeline(inputs: [BatchInput(path: root.appendingPathComponent("missing").path)], steps: []).items()
        }
        let empty = root.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        #expect(throws: ProjectError.self) { try BatchPipeline(inputs: [BatchInput(path: empty.path)], steps: []).items() }
        #expect(throws: ProjectError.self) {
            try BatchPipeline(inputs: [BatchInput(path: empty.path, kind: .project)], steps: []).items()
        }
    }

    @Test("Presets save by name, list, load and remove; saving needs a name and a step")
    func presets() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BatchPresetStore(root: root.appendingPathComponent("Presets"))
        #expect(store.list().isEmpty)
        var pipeline = BatchPipeline(name: "Vietsub TikTok", inputs: [], template: BatchTemplate(outputs: ["tiktok"]),
                                     steps: [BatchStep("export")])
        pipeline.extra = ["kept": .string("yes")]
        let url = try store.save(pipeline)
        #expect(url.lastPathComponent == "vietsub-tiktok.json")
        #expect(try store.load("vietsub tiktok") == pipeline)
        #expect(store.list().map(\.name) == ["Vietsub TikTok"])
        #expect(throws: ProjectError.self) { try store.load("Other") }
        #expect(throws: ProjectError.self) { try store.save(BatchPipeline(inputs: [], steps: [BatchStep("export")])) }
        #expect(throws: ProjectError.self) { try store.save(BatchPipeline(name: "Empty", inputs: [], steps: [])) }
        #expect(try store.remove("Vietsub TikTok"))
        #expect(try !store.remove("Vietsub TikTok"))
        #expect(BatchPresetStore.slug("Phụ đề Việt — đợt 2") == "phu-de-viet-dot-2")
    }

    @Test("Relative paths resolve against the pipeline file's folder; without one they are refused")
    func relativePaths() throws {
        let base = URL(fileURLWithPath: "/Users/me/batches", isDirectory: true)
        var pipeline = BatchPipeline(inputs: [BatchInput(path: "clips/a.mp4"), BatchInput(path: "/b.mp4"),
                                              BatchInput(path: "~/c.mp4")],
                                     steps: [BatchStep("project.save")], projectsFolder: "../projects")
        let resolved = try pipeline.resolvingPaths(against: base)
        #expect(resolved.inputs.map(\.path) == ["/Users/me/batches/clips/a.mp4", "/b.mp4", "~/c.mp4"])
        #expect(resolved.projectsFolder == "/Users/me/projects")
        try resolved.validate()
        // A preset saved before paths were resolved: the batch window has no folder to resolve "projects" against.
        let message = { (pipeline: BatchPipeline) -> String? in
            do { try pipeline.validate() } catch { return error.localizedDescription }
            return nil
        }
        #expect(message(pipeline)?.hasPrefix("../projects is a relative path") == true)
        #expect(throws: ProjectError.self) { try pipeline.resolvingPaths(against: nil) }
        pipeline.projectsFolder = "~/Movies/Batch"
        #expect(message(pipeline)?.hasPrefix("clips/a.mp4 is a relative path") == true)
        pipeline.inputs = []
        let saved = try pipeline.resolvingPaths(against: nil)
        #expect(saved.projectsFolder == "~/Movies/Batch")
    }

    @Test("A run's status counts items and reports the concurrency it used")
    func status() {
        let source = BatchItemSource(name: "a", url: URL(fileURLWithPath: "/a.mp4"), kind: .file)
        var pipeline = BatchPipeline(inputs: [BatchInput(path: "/a.mp4")], steps: [BatchStep("project.save")])
        pipeline.concurrency = 4
        var run = BatchRunStatus(id: "b1", pipeline: pipeline, items: [source, source], state: .running)
        run.items[0].state = .completed
        run.items[0].steps[0].outputs = ["/r/a.mp4"]
        let json = run.json().object
        #expect(json["counts"]?.object["completed"] == .integer(1))
        #expect(json["counts"]?.object["waiting"] == .integer(1))
        #expect(json["concurrency"] == .object(["asked": .integer(4), "used": .integer(1)]))
        #expect(json["items"]?.array.first?.object["outputs"] == .array([.string("/r/a.mp4")]))
        #expect(run.json(full: false).object["items"]?.array.first?.object["steps"] == nil)
        #expect(!BatchState.running.isFinished && BatchState.denied.isFinished)
    }
}
