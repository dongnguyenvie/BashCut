import BashCutProject
import BashCutTestSupport
import Foundation
import Testing

@testable import BashCutAutomation

/// The batch commands (P2-C1): one approval for the run, a pipeline file whose relative inputs resolve against its
/// folder, and status waits bounded like jobs wait.
struct BatchCommandTests {
    @Test("batch run reads pipeline.json, sets base to its folder and needs approval; status, cancel and presets")
    func specs() throws {
        let folder = try TestFixtures.temporaryDirectory("batch-cli")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("pipeline.json")
        try Data(#"{"inputs": ["clips"], "steps": [{"action": "export", "params": {"presets": "tiktok"}}]}"#.utf8).write(to: file)

        let run = try CommandLineParser.parse(["batch", "run", file.path, "--save-current"])
        #expect(run.spec.name == "batch.run")
        #expect(run.spec.execution == .approval && run.spec.mode == .privileged)
        #expect(run.params["pipeline"]?.object["inputs"] == .array([.string("clips")]))
        #expect(run.params["base"] == .string(folder.standardizedFileURL.path))
        #expect(run.params["saveCurrent"] == .bool(true))
        let given = try CommandLineParser.parse(["batch", "run", file.path, "--base", "/footage"])
        #expect(given.params["base"] == .string("/footage"))
        let preset = try CommandLineParser.parse(["batch", "run", "--preset", "Vietsub", "--inputs", "/a.mp4,/b.mp4"])
        #expect(preset.params["pipeline"] == nil && preset.params["base"] == nil)

        let status = try CommandLineParser.parse(["batch", "status", "batch-1", "--wait", "20"])
        #expect(status.spec.mode == .read && status.params["wait"] == .integer(20))
        #expect(throws: CommandLineParser.Failure.self) {
            try CommandLineParser.parse(["batch", "status", "--wait", "\(JobWaitDefaults.maximum + 1)"])
        }
        #expect(UnixRPCClient.readSeconds(RPCRequest(method: "batch.status", params: ["wait": .integer(20)])) == 30)
        #expect(CommandCatalog.spec(named: "batch.cancel")?.mode == .edit)
        let presets = try CommandLineParser.parse(["batch", "presets", file.path, "--name", "Draft"])
        #expect(presets.params["name"] == .string("Draft"))
        #expect(presets.params["base"] == .string(folder.standardizedFileURL.path))
        #expect(CommandCatalog.hiddenFromAgents.isSuperset(of: ["batch.cancel", "batch.presets"]))
        #expect(!CommandCatalog.hiddenFromAgents.contains("batch.run"))
    }
}
