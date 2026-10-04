import BashCutAgent
import BashCutPlugin
import BashCutProject
import Foundation
import Testing

@Suite("Terminal agents from plugins")
struct PluginTerminalTests {
    private struct Scratch {
        let root: URL
        let plugin: InstalledPlugin
        let agentFolder: URL
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            let directory = root.appendingPathComponent("plugin", isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent("bin"), withIntermediateDirectories: true)
            for name in ["bin/run", "bin/provider"] {
                let file = directory.appendingPathComponent(name)
                try Data("#!/bin/sh\n".utf8).write(to: file)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
            }
            let manifest = PluginManifest(
                id: "dev.example.gemini", name: "Gemini", version: "0.1.0", apiVersion: 5, entrypoint: "bin/provider",
                capabilities: ["agent.terminal"],
                providers: [
                    PluginProvider(id: "dev.example.gemini.terminal", capability: "agent.terminal", name: "Gemini"),
                ],
                terminal: PluginTerminal(icon: "sparkles", environment: ["GEMINI_*"]))
            try manifest.validate()
            plugin = InstalledPlugin(manifest: manifest, directory: directory)
            agentFolder = PluginTerminals.agentFolder(support: root, pluginID: plugin.id)
            try FileManager.default.createDirectory(at: agentFolder, withIntermediateDirectories: true)
        }

        func launch(_ fields: [String: JSONValue]) throws -> PluginTerminalLaunch {
            try PluginTerminalLaunch(result: .object(fields), pluginDirectory: plugin.directory, agentFolder: agentFolder)
        }
    }

    @Test("The plugin's command line launches with the manifest's environment and BashCut's session variables")
    func launch() throws {
        let scratch = try Scratch()
        defer { try? FileManager.default.removeItem(at: scratch.root) }
        let checked = try scratch.launch([
            "executable": .string("bin/run"), "arguments": .array([.string("--resume"), .string("abc")]),
            "directory": .string(scratch.agentFolder.path),
            "environment": .object(["GEMINI_CLI_SYSTEM_SETTINGS_PATH": .string("/tmp/settings.json")]),
            "skillsFolder": .string(scratch.agentFolder.appendingPathComponent(".gemini/skills").path),
        ])
        let provider = PluginTerminalProvider(plugin: scratch.plugin, launch: checked)
        #expect(provider.id.rawValue == "dev.example.gemini" && provider.title == "Gemini" && provider.author == .agent)
        let context = AgentSessionContext(
            project: nil, token: "token", socket: "/tmp/bashcut.sock", toolsDirectory: scratch.root.path, prompt: "")
        let launch = try AgentLaunch.make(
            provider: provider, workspace: scratch.root, context: context,
            environment: ["PATH": "", "GEMINI_API_KEY": "key", "OPENAI_API_KEY": "must-not-leak", "HOME": "/Users/test"])
        #expect(launch.executable == scratch.plugin.directory.appendingPathComponent("bin/run").path)
        #expect(launch.arguments == ["--resume", "abc"])
        #expect(launch.directory == scratch.agentFolder.path)
        #expect(launch.environment["GEMINI_API_KEY"] == "key")
        #expect(launch.environment["OPENAI_API_KEY"] == nil)
        #expect(launch.environment["GEMINI_CLI_SYSTEM_SETTINGS_PATH"] == "/tmp/settings.json")
        #expect(launch.environment["BASHCUT_SESSION_TOKEN"] == "token")
        #expect(checked.skillsFolder?.lastPathComponent == "skills")
    }

    @Test("A missing CLI is reported by name")
    func missing() throws {
        let scratch = try Scratch()
        defer { try? FileManager.default.removeItem(at: scratch.root) }
        let provider = PluginTerminalProvider(plugin: scratch.plugin, launch: try scratch.launch(["executable": .string("gemini")]))
        let context = AgentSessionContext(
            project: nil, token: "", socket: "/tmp/bashcut.sock", toolsDirectory: scratch.root.path, prompt: "")
        #expect(throws: AgentLaunchError.self) {
            try AgentLaunch.make(provider: provider, workspace: scratch.root, context: context, environment: ["PATH": ""])
        }
    }

    @Test("Launch answers that escape the plugin, the agent folder or the environment rules are refused")
    func refused() throws {
        let scratch = try Scratch()
        defer { try? FileManager.default.removeItem(at: scratch.root) }
        let gemini = JSONValue.string("gemini")
        let invalid: [[String: JSONValue]] = [
            [:],
            ["executable": .string("")],
            ["executable": .string("../outside")],
            ["executable": gemini, "arguments": .array([.integer(1)])],
            ["executable": gemini, "directory": .string("relative")],
            ["executable": gemini, "directory": .string("/no/such/folder")],
            ["executable": gemini, "environment": .object(["BASHCUT_SESSION_TOKEN": .string("x")])],
            ["executable": gemini, "environment": .object(["PATH": .string("/tmp")])],
            ["executable": gemini, "environment": .object(["A B": .string("x")])],
            ["executable": gemini, "skillsFolder": .string(scratch.root.path)],
            ["executable": gemini, "skillsFolder": .string(scratch.agentFolder.path + "/../other")],
        ]
        for fields in invalid {
            #expect(throws: PluginError.self) { try scratch.launch(fields) }
        }
    }

    @Test("Launch parameters carry the MCP server, the kit and the resume ID but never the token")
    func parameters() throws {
        let scratch = try Scratch()
        defer { try? FileManager.default.removeItem(at: scratch.root) }
        let params = PluginTerminals.launchParams(
            workspace: scratch.root, agentFolder: scratch.agentFolder, project: nil, prompt: "Use BashCut.",
            mcpExecutable: "/Apps/BashCut.app/Contents/MacOS/bashcut-mcp", kit: nil, resume: "abc", canEdit: false)
        #expect(params["op"]?.string == "launch")
        #expect(params["mcp"]?.object["command"]?.string == "/Apps/BashCut.app/Contents/MacOS/bashcut-mcp")
        #expect(params["kit"] == .null && params["project"] == .null && params["canEdit"] == .bool(false))
        #expect(params["resume"]?.string == "abc")
        let encoded = try #require(String(bytes: try JSONEncoder().encode(JSONValue.object(params)), encoding: .utf8))
        #expect(!encoded.contains("token\":") && !encoded.contains("automation.sock"))
        #expect(PluginTerminals.sessionID(from: .object(["id": .string("2f6c-session_1")])) == "2f6c-session_1")
        #expect(PluginTerminals.sessionID(from: .object(["id": .string("bad id; rm")])) == nil)
        #expect(PluginTerminals.sessionID(from: .object(["id": .null])) == nil)
    }

    @Test("Skills are linked into the agent folder and unlinked when the kit is off")
    func skills() throws {
        let scratch = try Scratch()
        defer { try? FileManager.default.removeItem(at: scratch.root) }
        let kitRoot = scratch.root.appendingPathComponent("kit", isDirectory: true)
        try FileManager.default.createDirectory(
            at: kitRoot.appendingPathComponent(".claude-plugin"), withIntermediateDirectories: true)
        try Data(#"{"version": "1.2.0"}"#.utf8).write(to: kitRoot.appendingPathComponent(".claude-plugin/plugin.json"))
        let skill = kitRoot.appendingPathComponent("skills/bashcut-cut", isDirectory: true)
        try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
        try Data("---\nname: bashcut-cut\ndescription: Cut the timeline\n---\n".utf8)
            .write(to: skill.appendingPathComponent("SKILL.md"))
        let kit = try #require(AgentKit(root: kitRoot, source: .folder))
        let folder = scratch.agentFolder.appendingPathComponent(".gemini/skills", isDirectory: true)
        try AgentKitInstall.syncSkills(of: kit, into: folder)
        #expect(AgentKitInstall.linkedSkills(of: kit, in: folder) == ["bashcut-cut"])
        #expect(PluginTerminals.kitJSON(kit).object["skills"]?.array.first?.object["description"]?.string == "Cut the timeline")
        try AgentKitInstall.syncSkills(of: nil, into: folder)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }
}
