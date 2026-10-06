import BashCutAgent
import Foundation
import Testing

struct AgentLaunchTests {
    @Test("Claude resumes its project session without inheriting an API key")
    func claudeResume() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("claude")
        try Data().write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let context = AgentSessionContext(
            project: root.appendingPathComponent("project.bashcut.json"), token: "token",
            socket: root.appendingPathComponent("automation.sock").path,
            toolsDirectory: root.path, prompt: "Use BashCut.")
        let launch = try AgentLaunch.make(
            provider: ClaudeAgentProvider(), workspace: root, context: context, resumeID: "claude-session",
            environment: ["PATH": "", "ANTHROPIC_API_KEY": "must-not-leak", "HOME": "/Users/test"])
        #expect(launch.arguments.prefix(2) == ["--resume", "claude-session"])
        #expect(launch.arguments.contains("--append-system-prompt"))
        let mcpIndex = try #require(launch.arguments.firstIndex(of: "--mcp-config"))
        #expect(launch.arguments[mcpIndex + 1].contains("bashcut-mcp"))
        #expect(launch.environment["ANTHROPIC_API_KEY"] == nil)
        #expect(launch.environment["HOME"] == "/Users/test")
        #expect(launch.environment["BASHCUT_SESSION_TOKEN"] == "token")
        #expect(launch.directory == root.path)
    }

    @Test("Session bookmarks persist separately per canonical project")
    func sessionBookmarks() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentSessionStore(url: root.appendingPathComponent("sessions.json"))
        let first = root.appendingPathComponent("one/project.bashcut.json")
        let second = root.appendingPathComponent("two/project.bashcut.json")
        try store.save(AgentSessionBookmarks([.claude: "claude-one", .codex: "codex-one"]), project: first)
        try store.save(AgentSessionBookmarks([.claude: "claude-two", .codex: ""]), project: second)
        #expect(try store.load(project: first) == AgentSessionBookmarks([.claude: "claude-one", .codex: "codex-one"]))
        #expect(try store.load(project: second) == AgentSessionBookmarks([.claude: "claude-two"]))
        #expect(try store.load(project: second)[.codex] == "")
        let permissions = try #require(
            FileManager.default.attributesOfItem(atPath: store.url.path)[.posixPermissions] as? Int)
        #expect(permissions & 0o777 == 0o600)
    }

    @Test("Session discovery matches Claude workspace and Codex project metadata")
    func sessionDiscovery() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let claudeRoot = root.appendingPathComponent("claude", isDirectory: true)
        let codexRoot = root.appendingPathComponent("codex/2026/10/02", isDirectory: true)
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        let project = workspace.appendingPathComponent("review/project.bashcut.json")
        try FileManager.default.createDirectory(at: claudeRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codexRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let claudeID = "51df231d-a6a5-422a-882b-8124e9e41801"
        let codexID = "01a0f92b-934a-7a90-8cd4-c27504221d75"
        try jsonLines([
            ["type": "user", "sessionId": claudeID, "cwd": workspace.path]
        ]).write(to: claudeRoot.appendingPathComponent(claudeID + ".jsonl"))
        try jsonLines([
            ["type": "session_meta", "payload": [
                "id": codexID, "cwd": root.appendingPathComponent("agent-workspace").path,
            ]],
            ["type": "response_item", "payload": ["text": "Edit " + project.path]],
        ]).write(to: codexRoot.appendingPathComponent("rollout-" + codexID + ".jsonl"))
        let discovery = AgentSessionDiscovery(
            roots: [.claude: claudeRoot, .codex: root.appendingPathComponent("codex"), .shell: root])

        #expect(discovery.latest(provider: ClaudeAgentProvider(), project: project, workspace: workspace) == claudeID)
        #expect(discovery.latest(provider: CodexAgentProvider(), project: project, workspace: workspace) == codexID)
        #expect(discovery.latest(provider: ShellAgentProvider(), project: project, workspace: workspace) == nil)
    }

    @Test("Session discovery reads only new or changed files on the next scan")
    func sessionDiscoveryCache() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let claudeRoot = root.appendingPathComponent("claude", isDirectory: true)
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        let project = root.appendingPathComponent("films/trip/project.bashcut.json")
        try FileManager.default.createDirectory(at: claudeRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let other = "6f1c1f0e-5d3a-4c55-9d5b-0a4b8a3c2e11"
        let matching = "9b7e3c2a-1d4f-4e6a-8b9c-2f3e4d5a6b7c"
        try jsonLines([["type": "user", "sessionId": other, "cwd": "/somewhere/else"]])
            .write(to: claudeRoot.appendingPathComponent(other + ".jsonl"))
        let cache = AgentSessionDiscovery.Cache()
        let discovery = AgentSessionDiscovery(roots: [.claude: claudeRoot], cache: cache)
        let provider = ClaudeAgentProvider()

        #expect(discovery.latest(provider: provider, project: project, workspace: workspace) == nil)
        #expect(cache.reads == 1)
        #expect(discovery.latest(provider: provider, project: project, workspace: workspace) == nil)
        #expect(cache.reads == 1)

        let file = claudeRoot.appendingPathComponent(matching + ".jsonl")
        try jsonLines([["type": "user", "sessionId": matching, "text": "Open " + project.path]]).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: file.path)
        #expect(discovery.latest(provider: provider, project: project, workspace: workspace) == matching)
        #expect(cache.reads == 2)
        #expect(discovery.latest(provider: provider, project: project, workspace: workspace) == matching)
        #expect(cache.reads == 2)
    }

    @Test("Codex uses the low-cost model and a socket-scoped permission profile")
    func codexLaunchPolicy() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("codex")
        try Data().write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let socket = root.appendingPathComponent("Agent Socket/automation.sock").path
        let context = AgentSessionContext(
            project: root.appendingPathComponent("project.bashcut.json"), token: "token",
            socket: socket, toolsDirectory: root.path, prompt: "Use BashCut.\nDo not edit JSON.")

        let launch = try AgentLaunch.make(
            provider: CodexAgentProvider(), workspace: root, context: context, resumeID: "codex-session",
            environment: ["PATH": "", "OPENAI_API_KEY": "codex-key", "AWS_SECRET_ACCESS_KEY": "app-secret"])

        #expect(launch.arguments.starts(with: ["-m", "gpt-5.6-luna"]))
        #expect(launch.arguments.contains("model_reasoning_effort=\"low\""))
        #expect(launch.arguments.contains("features.network_proxy=true"))
        #expect(launch.arguments.contains(where: { argument in
            argument.contains("mcp_servers.bashcut=") && argument.contains("bashcut-mcp")
                && argument.contains("BASHCUT_SESSION_TOKEN")
        }))
        #expect(launch.arguments.contains(where: { argument in
            argument.contains("permissions.bashcut=") && argument.contains(socket)
                && argument.contains("unix_sockets")
        }))
        #expect(launch.arguments.contains(where: { argument in
            argument.hasPrefix("developer_instructions=") && argument.contains("Use BashCut")
        }))
        #expect(launch.arguments.suffix(2) == ["resume", "codex-session"])
        #expect(!launch.arguments.contains(context.prompt))
        #expect(launch.directory.hasSuffix("/Agent Socket/agent-workspace"))
        #expect(FileManager.default.fileExists(atPath: launch.directory))
        #expect(launch.environment["OPENAI_API_KEY"] == "codex-key")
        #expect(launch.environment["AWS_SECRET_ACCESS_KEY"] == nil)
    }

    @Test("Bookmarks written by earlier builds load by provider ID")
    func legacyBookmarks() throws {
        let legacy = #"{"claude":"claude-id","codex":""}"#
        let bookmarks = try JSONDecoder().decode(AgentSessionBookmarks.self, from: Data(legacy.utf8))
        #expect(bookmarks[.claude] == "claude-id")
        #expect(bookmarks[.codex] == "")
        let encoded = try JSONDecoder().decode(
            [String: String].self, from: JSONEncoder().encode(bookmarks))
        #expect(encoded == ["claude": "claude-id"])
    }

    @Test("Terminals inherit only allowlisted variables and providers have unique IDs")
    func environmentAllowlist() {
        let environment = [
            "HOME": "/h", "LC_ALL": "vi_VN.UTF-8", "HTTPS_PROXY": "http://proxy", "GITHUB_TOKEN": "secret",
            "ANTHROPIC_API_KEY": "secret", "CLAUDE_CONFIG_DIR": "/c", "BASHCUT_SESSION_TOKEN": "parent",
        ]
        let shell = AgentEnvironment.filtered(environment, allowing: ShellAgentProvider().environmentAllowlist)
        #expect(shell == ["HOME": "/h", "LC_ALL": "vi_VN.UTF-8", "HTTPS_PROXY": "http://proxy"])
        let claude = AgentEnvironment.filtered(environment, allowing: ClaudeAgentProvider().environmentAllowlist)
        #expect(claude["CLAUDE_CONFIG_DIR"] == "/c")
        #expect(claude["ANTHROPIC_API_KEY"] == nil)
        #expect(Set(AgentProviders.all.map(\.id)).count == AgentProviders.all.count)
        #expect(AgentProviders.agents.map(\.id) == [.claude, .codex])
    }

    private func jsonLines(_ values: [[String: Any]]) throws -> Data {
        var data = Data()
        for value in values {
            data.append(try JSONSerialization.data(withJSONObject: value))
            data.append(0x0A)
        }
        return data
    }
}
