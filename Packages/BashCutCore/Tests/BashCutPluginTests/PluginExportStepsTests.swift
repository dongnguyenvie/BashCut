import BashCutPlugin
import BashCutProject
import BashCutProjectFixtures
import Foundation
import Testing

@Suite("Plugin export steps (API 12, #634)")
struct PluginExportStepsTests {
    private func manifest(_ steps: String, apiVersion: Int = 12) throws -> PluginManifest {
        try JSONDecoder().decode(PluginManifest.self, from: Data("""
            {"schema": "bashcut.plugin/1", "id": "example.graphics", "name": "Graphics", "version": "1.0.0",
             "apiVersion": \(apiVersion), "entrypoint": "bin/provider", "capabilities": ["graphics.render"],
             "contributes": {"exportSteps": \(steps)}}
            """.utf8))
    }

    private let finalise = """
        [{"id": "finalise", "title": {"en": "Finalise draft graphics", "vi": "Hoàn thiện đồ hoạ nháp"},
          "command": {"executable": "bin/graphic", "arguments": ["rerender", "--all", "--final"]},
          "when": "media.data.graphics.draft"}]
        """

    @Test("A step decodes and validates from API 12; older manifests and the host feature list know it")
    func decodes() throws {
        let plugin = try manifest(finalise)
        try plugin.validate()
        let step = try #require(plugin.exportSteps.first)
        #expect(step.command == PluginCommand(executable: "bin/graphic", arguments: ["rerender", "--all", "--final"]))
        #expect(step.condition?.path == ["graphics", "draft"])
        #expect(step.timeout == 1800)
        #expect(PluginAPI.current >= 12)
        #expect(PluginFeature.all.contains(PluginFeature.exportSteps))
        #expect(throws: PluginError.invalid("contributes.exportSteps needs apiVersion 12")) {
            try manifest(finalise, apiVersion: 11).validate()
        }
    }

    @Test("Steps run a file inside the plugin, with a media.data condition, unique ids and a sane timeout")
    func invalid() throws {
        func step(_ fields: String) -> String {
            #"[{"id": "finalise", "title": "Finalise", "command": {"executable": "bin/graphic"}, "when": "media.data.graphics.draft"\#(fields)}]"#
        }
        for bad in [
            #"[{"id": "a", "title": "A", "command": {"executable": "/bin/sh"}, "when": "media.data.x"}]"#,
            #"[{"id": "a", "title": "A", "command": {"executable": "node"}, "when": "media.data.x"}]"#,
            #"[{"id": "a", "title": "A", "command": {"executable": "bin/../../x"}, "when": "media.data.x"}]"#,
            #"[{"id": "a", "title": "A", "command": {"executable": "bin/x"}, "when": "selection.kind"}]"#,
            #"[{"id": "a", "title": "A", "command": {"executable": "bin/x"}, "when": "media.data"}]"#,
            #"[{"id": "a", "title": "A", "command": {"executable": "bin/x"}, "when": "media.data.a b"}]"#,
            step(#", "timeoutSeconds": 5"#),
        ] {
            #expect(throws: PluginError.self) { try manifest(bad).validate() }
        }
        let twice = #"[{"id": "a", "title": "A", "command": {"executable": "bin/x"}, "when": "media.data.x"}, "#
            + #"{"id": "a", "title": "B", "command": {"executable": "bin/y"}, "when": "media.data.y"}]"#
        #expect(throws: PluginError.self) { try manifest(twice).validate() }
        try manifest(step(#", "timeoutSeconds": 600"#)).validate()
    }

    @Test("when holds for media a timeline item uses with a truthy value; media without data.graphics never counts")
    func condition() throws {
        let condition = try PluginExportStepCondition(parsing: "media.data.graphics.draft")
        var project = try ProjectFixtures.linkedPair()
        #expect(!condition.holds(for: project))
        project = try project.applying(.setMediaData(media: "m", patch: ["take": .integer(2)])).project
        #expect(!condition.holds(for: project))
        let final: JSONValue = .object(["name": .string("Flow"), "fps": .integer(30)])
        project = try project.applying(.setMediaData(media: "m", patch: ["graphics": final])).project
        #expect(!condition.holds(for: project))
        project = try project.applying(.setMediaData(
            media: "m", patch: ["graphics": .object(["name": .string("Flow"), "draft": .bool(true)])])).project
        #expect(condition.matchingMedia(project) == ["m"])
        project = try project.applying(.setMediaData(
            media: "m", patch: ["graphics": .object(["name": .string("Flow"), "draft": .bool(false)])])).project
        #expect(!condition.holds(for: project))
        project = try project.applying(.setMediaData(
            media: "m", patch: ["graphics": .object(["draft": .bool(true)])])).project
        // A draft no item uses is not exported.
        project = try project.applying(.delete(item: "v", ripple: false)).project
        #expect(!condition.holds(for: project))
    }
}
