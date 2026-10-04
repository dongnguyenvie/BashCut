import Foundation
import Testing

@testable import BashCutAgent

struct AgentKitTests {
    private func temporaryFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// A kit with `skills` at `root`.
    @discardableResult
    private func makeKit(at root: URL, version: String = "0.0.1", skills: [String] = ["bashcut-one", "bashcut-two"])
        throws -> URL
    {
        let manager = FileManager.default
        try manager.createDirectory(at: root.appendingPathComponent(".claude-plugin"), withIntermediateDirectories: true)
        try Data(#"{"name":"bashcut","version":"\#(version)"}"#.utf8)
            .write(to: root.appendingPathComponent(".claude-plugin/plugin.json"))
        try Data("{}".utf8).write(to: root.appendingPathComponent(".mcp.json"))
        for name in skills {
            let folder = root.appendingPathComponent("skills/\(name)", isDirectory: true)
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("---\nname: \(name)\n---\n".utf8).write(to: folder.appendingPathComponent("SKILL.md"))
        }
        return root
    }

    @Test("A kit needs a plugin manifest and skills; a chosen folder wins over the built-in kit")
    func locate() throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let resources = root.appendingPathComponent("Resources", isDirectory: true)
        try makeKit(at: resources.appendingPathComponent("AgentKit"), version: "1.0.0")
        let folder = try makeKit(at: root.appendingPathComponent("checkout"), version: "2.0.0")
        #expect(AgentKit(root: root, source: .folder) == nil)
        #expect(AgentKit.locate(folder: nil, resources: resources)?.version == "1.0.0")
        #expect(AgentKit.locate(folder: folder, resources: resources)?.source == .folder)
        #expect(AgentKit.locate(folder: root, resources: resources)?.source == .bundled)
        #expect(AgentKit.locate(folder: nil, resources: root)?.skills == nil)
        #expect(AgentKit(root: folder, source: .folder)?.skills == ["bashcut-one", "bashcut-two"])
    }

    @Test("The built-in kit is copied to a stable folder and refreshed when its version changes")
    func stableCopy() throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let install = AgentKitInstall(support: root.appendingPathComponent("support"))
        let bundled = try #require(AgentKit(root: makeKit(at: root.appendingPathComponent("app")), source: .bundled))
        let first = try install.stableRoot(for: bundled)
        #expect(first.root == root.appendingPathComponent("support/agent-kit").standardizedFileURL)
        #expect(first.skills == bundled.skills)
        try makeKit(at: root.appendingPathComponent("app"), version: "0.0.2", skills: ["bashcut-one", "bashcut-three"])
        let updated = try #require(AgentKit(root: root.appendingPathComponent("app"), source: .bundled))
        let second = try install.stableRoot(for: updated)
        #expect(second.version == "0.0.2")
        #expect(second.skills == ["bashcut-one", "bashcut-three", "bashcut-two"])
        let folder = try #require(AgentKit(root: root.appendingPathComponent("app"), source: .folder))
        #expect(try install.stableRoot(for: folder).root == folder.root)
    }

    @Test("Unchanged kit content keeps the installed directory; same-version content changes refresh it")
    func contentRefresh() throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let install = AgentKitInstall(support: root.appendingPathComponent("support"))
        let bundled = try #require(AgentKit(root: makeKit(at: root.appendingPathComponent("app")), source: .bundled))
        let first = try install.stableRoot(for: bundled)
        let inode = try FileManager.default.attributesOfItem(atPath: first.root.path)[.systemFileNumber] as? NSNumber
        _ = try install.stableRoot(for: bundled)
        #expect(try FileManager.default.attributesOfItem(atPath: first.root.path)[.systemFileNumber] as? NSNumber == inode)
        let skill = "skills/bashcut-one/SKILL.md"
        try Data("Updated editing instructions".utf8).write(to: bundled.root.appendingPathComponent(skill))
        let second = try install.stableRoot(for: bundled)
        #expect(second.version == first.version)
        #expect(try String(contentsOf: second.root.appendingPathComponent(skill), encoding: .utf8) == "Updated editing instructions")
        let helper = "skills/bashcut-one/helper.py"
        try Data("print('updated helper')".utf8).write(to: bundled.root.appendingPathComponent(helper))
        _ = try install.stableRoot(for: bundled)
        #expect(FileManager.default.fileExists(atPath: first.root.appendingPathComponent(helper).path))
        try FileManager.default.removeItem(at: bundled.root.appendingPathComponent(helper))
        _ = try install.stableRoot(for: bundled)
        #expect(!FileManager.default.fileExists(atPath: first.root.appendingPathComponent(helper).path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: install.support.path) == ["agent-kit"])
    }

    @Test("Invalid bundled content leaves the last installed kit intact")
    func failedRefreshPreservesInstalledKit() throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let install = AgentKitInstall(support: root.appendingPathComponent("support"))
        let bundled = try #require(AgentKit(root: makeKit(at: root.appendingPathComponent("app")), source: .bundled))
        let installed = try install.stableRoot(for: bundled)
        let hash = try installed.contentHash()
        try FileManager.default.createSymbolicLink(
            at: bundled.skillsFolder.appendingPathComponent("external"), withDestinationURL: root)
        #expect(throws: AgentKitError.self) { try install.stableRoot(for: bundled) }
        #expect(try installed.contentHash() == hash)
        #expect(try FileManager.default.contentsOfDirectory(atPath: install.support.path) == ["agent-kit"])
    }

    @Test("BashCut's Claude tabs get a skills-only plugin, without the kit's MCP server")
    func claudePlugin() throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let kit = try #require(AgentKit(root: makeKit(at: root.appendingPathComponent("kit")), source: .folder))
        let plugin = try AgentKitInstall(support: root).claudePlugin(for: kit)
        let manifest = try JSONSerialization.jsonObject(
            with: Data(contentsOf: plugin.appendingPathComponent(".claude-plugin/plugin.json"))) as? [String: Any]
        #expect(manifest?["name"] as? String == "bashcut")
        #expect(FileManager.default.fileExists(atPath: plugin.appendingPathComponent("skills/bashcut-one/SKILL.md").path))
        #expect(!FileManager.default.fileExists(atPath: plugin.appendingPathComponent(".mcp.json").path))
        _ = try AgentKitInstall(support: root).claudePlugin(for: kit)  // again: replaces its own link

        let claude = root.appendingPathComponent("claude")
        try Data().write(to: claude)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claude.path)
        let context = AgentSessionContext(
            project: nil, token: "token", socket: root.appendingPathComponent("automation.sock").path,
            toolsDirectory: root.path, prompt: "Use BashCut.")
        let launch = try AgentLaunch.make(
            provider: ClaudeAgentProvider(), workspace: root, context: context,
            kit: AgentKitLaunch(kit: kit, claudePlugin: plugin), environment: ["PATH": ""])
        let index = try #require(launch.arguments.firstIndex(of: "--plugin-dir"))
        #expect(launch.arguments[index + 1] == plugin.path)
        let plain = try AgentLaunch.make(
            provider: ClaudeAgentProvider(), workspace: root, context: context, environment: ["PATH": ""])
        #expect(!plain.arguments.contains("--plugin-dir"))
    }

    @Test("Codex tabs see exactly the kit's skills in their working folder")
    func codexSkills() throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let kit = try #require(AgentKit(root: makeKit(at: root.appendingPathComponent("kit")), source: .folder))
        let codex = root.appendingPathComponent("codex")
        try Data().write(to: codex)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: codex.path)
        let socketFolder = root.appendingPathComponent("support", isDirectory: true)
        let context = AgentSessionContext(
            project: nil, token: "token", socket: socketFolder.appendingPathComponent("automation.sock").path,
            toolsDirectory: root.path, prompt: "Use BashCut.")
        let launch = try AgentLaunch.make(
            provider: CodexAgentProvider(), workspace: root, context: context,
            kit: AgentKitLaunch(kit: kit, claudePlugin: root), environment: ["PATH": ""])
        let skills = URL(fileURLWithPath: launch.directory).appendingPathComponent(".agents/skills")
        #expect(AgentKitInstall.linkedSkills(of: kit, in: skills) == kit.skills)

        _ = try AgentLaunch.make(provider: CodexAgentProvider(), workspace: root, context: context, environment: ["PATH": ""])
        #expect((try? FileManager.default.contentsOfDirectory(atPath: skills.path)) == [])
    }

    @Test("Linking skills never replaces a real folder, and unlinking removes only links")
    func linking() throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let kit = try #require(AgentKit(root: makeKit(at: root.appendingPathComponent("kit")), source: .folder))
        let skills = root.appendingPathComponent("home/.agents/skills", isDirectory: true)
        try FileManager.default.createDirectory(
            at: skills.appendingPathComponent("bashcut-two"), withIntermediateDirectories: true)
        #expect(try AgentKitInstall.linkSkills(of: kit, into: skills) == ["bashcut-one"])
        #expect(AgentKitInstall.linkedSkills(of: kit, in: skills) == ["bashcut-one"])
        #expect(AgentKitInstall.unlinkSkills(named: kit.skills, in: skills) == ["bashcut-one"])
        #expect(FileManager.default.fileExists(atPath: skills.appendingPathComponent("bashcut-two").path))
    }

    @Test("Agent configuration folders come from Settings, then the environment, then the login shell")
    func configFolders() {
        let home = URL(fileURLWithPath: "/Users/test")
        let standard = AgentConfigFolders.resolve(
            claudeSetting: nil, codexSetting: nil, environment: [:], shell: [:], home: home)
        #expect(standard.claude.url.path == "/Users/test/.claude" && standard.claude.origin == .standard)
        #expect(standard.applied(to: ["HOME": "/Users/test"]) == ["HOME": "/Users/test"])

        let shell = AgentConfigFolders.resolve(
            claudeSetting: nil, codexSetting: nil, environment: [:],
            shell: ["CLAUDE_CONFIG_DIR": "/Users/test/.claude-work", "CODEX_HOME": "/Users/test/.codex-work"], home: home)
        #expect(shell.claude.origin == .shell)
        #expect(shell.applied(to: [:]) == [
            "CLAUDE_CONFIG_DIR": "/Users/test/.claude-work", "CODEX_HOME": "/Users/test/.codex-work",
        ])

        let chosen = AgentConfigFolders.resolve(
            claudeSetting: URL(fileURLWithPath: "/Volumes/x/claude"), codexSetting: nil,
            environment: ["CLAUDE_CONFIG_DIR": "/env/claude", "CODEX_HOME": "/env/codex"],
            shell: ["CODEX_HOME": "/shell/codex"], home: home)
        #expect(chosen.claude.url.path == "/Volumes/x/claude" && chosen.claude.origin == .settings)
        #expect(chosen.codex.url.path == "/env/codex" && chosen.codex.origin == .environment)
    }

    @Test("Only what the login shell prints after the marker counts")
    func shellOutput() {
        let output = "Welcome!\n__M__/Users/test/.claude-work\n\n"
        #expect(AgentConfigFolders.parse(output, marker: "__M__") == ["CLAUDE_CONFIG_DIR": "/Users/test/.claude-work"])
        #expect(AgentConfigFolders.parse("no marker", marker: "__M__").isEmpty)
    }
}
