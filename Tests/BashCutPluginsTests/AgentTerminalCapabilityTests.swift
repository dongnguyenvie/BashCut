import BashCutAgent
import BashCutPlugin
import BashCutProject
import Foundation
import Testing

@testable import BashCutPlugins

/// A one-shot `agent.terminal` plugin (Python standard library): `launch` writes a settings file in the agent folder
/// and answers with a command line; `session` answers with a fixed ID.
private let terminalScript = #"""
#!/usr/bin/env python3
import json, os, sys

request = json.loads(sys.stdin.readline())
params = request["params"]
if params["op"] == "launch":
    folder = params["agentFolder"]
    os.makedirs(os.path.join(folder, ".fake"), exist_ok=True)
    with open(os.path.join(folder, ".fake", "settings.json"), "w") as out:
        json.dump({"mcpServers": {params["mcp"]["name"]: {"command": params["mcp"]["command"]}}}, out)
    args = ["--resume", params["resume"]] if params["resume"] else []
    result = {"executable": "fake-cli", "arguments": args, "directory": folder,
              "skillsFolder": os.path.join(folder, ".fake", "skills"), "options": params["options"],
              "sawToken": "BASHCUT_SESSION_TOKEN" in os.environ}
elif params["op"] == "session":
    result = {"id": "session-42"}
else:
    print(json.dumps({"id": request["id"], "error": {"code": "unknown", "message": "Unknown op"}}))
    sys.exit(0)
print(json.dumps({"id": request["id"], "result": result}))
"""#

@Suite("agent.terminal capability")
struct AgentTerminalCapabilityTests {
    @Test("launch and session reach a one-shot plugin with its options, and its answer passes validation")
    func launchAndSession() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("terminal-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("user/dev.example.fake", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let entrypoint = directory.appendingPathComponent("provider.py")
        try Data(terminalScript.utf8).write(to: entrypoint)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: entrypoint.path)
        let manifest = PluginManifest(
            id: "dev.example.fake", name: "Fake CLI", version: "1.0.0", apiVersion: 5, entrypoint: "provider.py",
            capabilities: ["agent.terminal"],
            providers: [PluginProvider(id: "dev.example.fake.terminal", capability: "agent.terminal", name: "Fake")],
            options: [PluginOption(id: "model", title: "Model", type: .string, default: .string("flash"))],
            terminal: PluginTerminal(environment: ["FAKE_*"]))
        try manifest.validate()
        try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("plugin.json"))

        var service = CapabilityService(roots: PluginRoots(user: root.appendingPathComponent("user"), bundled: nil))
        service.optionValues = { _ in ["model": .string("flash")] }
        let resolved = try await service.resolve("agent.terminal", preferredProvider: nil, projectRoot: nil)
        let agentFolder = PluginTerminals.agentFolder(support: root, pluginID: manifest.id)
        try FileManager.default.createDirectory(at: agentFolder, withIntermediateDirectories: true)

        let params = PluginTerminals.launchParams(
            workspace: root, agentFolder: agentFolder, project: nil, prompt: "Use BashCut.",
            mcpExecutable: "/tmp/bashcut-mcp", kit: nil, resume: "abc", canEdit: true)
        let result = try await service.terminal(params, using: resolved)
        #expect(result.object["options"]?.object["model"]?.string == "flash")
        #expect(result.object["sawToken"]?.bool == false)
        let launch = try PluginTerminalLaunch(result: result, pluginDirectory: directory, agentFolder: agentFolder)
        #expect(launch.executable == "fake-cli" && launch.arguments == ["--resume", "abc"])
        #expect(FileManager.default.fileExists(atPath: agentFolder.appendingPathComponent(".fake/settings.json").path))

        let session = try await service.terminal(
            PluginTerminals.sessionParams(workspace: root, agentFolder: agentFolder, project: root, notBefore: Date()),
            using: resolved)
        #expect(PluginTerminals.sessionID(from: session) == "session-42")
    }
}
