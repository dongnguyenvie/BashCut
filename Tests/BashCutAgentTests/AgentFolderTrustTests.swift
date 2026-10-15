@testable import BashCutAgent
import BashCutTestSupport
import Foundation
import Testing

struct AgentFolderTrustTests {
    /// Config folders set in Settings, so nothing reads or writes the real `~/.claude.json` or `~/.codex`.
    private func trust(_ root: URL) -> AgentFolderTrust {
        AgentFolderTrust(folders: .resolve(
            claudeSetting: root.appendingPathComponent("claude"), codexSetting: root.appendingPathComponent("codex"),
            environment: [:], shell: [:], home: root.appendingPathComponent("home")))
    }

    private func folder(_ root: URL, _ path: String) throws -> URL {
        let url = root.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Claude: the standard folder's config is ~/.claude.json, a chosen one's is inside it")
    func claudeConfigFile() {
        let home = URL(fileURLWithPath: "/Users/someone")
        let standard = AgentFolderTrust(folders: .resolve(claudeSetting: nil, codexSetting: nil, environment: [:], shell: [:], home: home))
        #expect(standard.claudeConfig.path == "/Users/someone/.claude.json")
        #expect(standard.codexConfig.path == "/Users/someone/.codex/config.toml")
        let moved = AgentFolderTrust(folders: .resolve(
            claudeSetting: nil, codexSetting: nil, environment: ["CLAUDE_CONFIG_DIR": "/cfg/claude-2"], shell: [:], home: home))
        #expect(moved.claudeConfig.path == "/cfg/claude-2/.claude.json")
    }

    @Test("Claude: trusting merges into .claude.json under the raw and resolved paths and keeps other keys")
    func claudeMerge() throws {
        let root = try TestFixtures.temporaryDirectory("trust")
        let trust = trust(root)
        let work = try folder(root, "work")
        try FileManager.default.createDirectory(at: trust.claudeConfig.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existing = #"{"oauthAccount":{"email":"a@b.c"},"numStartups":7,"projects":{"/other":{"allowedTools":["Bash"]}}}"#
        try Data(existing.utf8).write(to: trust.claudeConfig)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: trust.claudeConfig.path)
        #expect(!trust.isTrusted(.claude, folder: work))

        try trust.trust(.claude, folder: work)
        #expect(trust.isTrusted(.claude, folder: work))
        let config = try #require(try AgentFolderTrust.readJSON(trust.claudeConfig))
        #expect((config["oauthAccount"] as? [String: Any])?["email"] as? String == "a@b.c")
        #expect(config["numStartups"] as? Int == 7)
        let projects = try #require(config["projects"] as? [String: Any])
        #expect((projects["/other"] as? [String: Any])?["allowedTools"] as? [String] == ["Bash"])
        let raw = work.path
        // Temporary folders are under /var, a symlink to /private/var; the CLIs read the real path.
        let real = "/private" + raw
        #expect(raw.hasPrefix("/var/"))
        for key in [raw, real] {
            #expect((projects[key] as? [String: Any])?["hasTrustDialogAccepted"] as? Bool == true)
        }
        let permissions = try FileManager.default.attributesOfItem(atPath: trust.claudeConfig.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
        // No temporary files are left beside it.
        let names = try FileManager.default.contentsOfDirectory(atPath: trust.claudeConfig.deletingLastPathComponent().path)
        #expect(names == [".claude.json"])
    }

    @Test("Claude: a folder in a repository is trusted by the repository's root; a trusted parent covers folders below")
    func claudeKeys() throws {
        let root = try TestFixtures.temporaryDirectory("trust")
        let trust = trust(root)
        let repo = try folder(root, "projects/repo")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let inner = try folder(root, "projects/repo/sub")
        try trust.trust(.claude, folder: inner)
        let projects = try #require(try AgentFolderTrust.readJSON(trust.claudeConfig)?["projects"] as? [String: Any])
        #expect(projects["/private" + repo.path] != nil)
        #expect(projects["/private" + inner.path] == nil)
        #expect(trust.isTrusted(.claude, folder: inner))

        let plain = try folder(root, "projects/plain/deep")
        #expect(!trust.isTrusted(.claude, folder: plain))
        try trust.trust(.claude, folder: root.appendingPathComponent("projects"))
        #expect(trust.isTrusted(.claude, folder: plain))
        // Claude Code stops at a repository's root, so a trusted parent above it does not count.
        let other = try folder(root, "projects/other-repo")
        try FileManager.default.createDirectory(at: other.appendingPathComponent(".git"), withIntermediateDirectories: true)
        #expect(!trust.isTrusted(.claude, folder: other))
    }

    @Test("Claude: a file that is not JSON is left alone")
    func claudeUnreadable() throws {
        let root = try TestFixtures.temporaryDirectory("trust")
        let trust = trust(root)
        try FileManager.default.createDirectory(at: trust.claudeConfig.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: trust.claudeConfig)
        #expect(throws: (any Error).self) { try trust.trust(.claude, folder: root) }
        #expect(try String(contentsOf: trust.claudeConfig, encoding: .utf8) == "{ not json")
    }

    @Test("Codex: trusting adds a projects table and keeps the rest of config.toml")
    func codexAppend() throws {
        let root = try TestFixtures.temporaryDirectory("trust")
        let trust = trust(root)
        let work = try folder(root, "work")
        try FileManager.default.createDirectory(at: trust.codexConfig.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existing = "# mine\nmodel = \"gpt\"\n\n[projects.\"/other\"]\ntrust_level = \"trusted\"\n"
        try existing.write(to: trust.codexConfig, atomically: true, encoding: .utf8)
        #expect(!trust.isTrusted(.codex, folder: work))
        try trust.trust(.codex, folder: work)
        #expect(trust.isTrusted(.codex, folder: work))
        let text = try String(contentsOf: trust.codexConfig, encoding: .utf8)
        #expect(text.hasPrefix(existing))
        #expect(text.contains("[projects.\"\("/private" + work.path)\"]\ntrust_level = \"trusted\""))
        // Trusting again changes nothing.
        try trust.trust(.codex, folder: work)
        #expect(try String(contentsOf: trust.codexConfig, encoding: .utf8) == text)
    }

    @Test("Codex: an untrusted project becomes trusted in place; an inline projects table is not edited")
    func codexEdit() throws {
        let text = "[projects.\"/a\"]\ntrust_level = \"untrusted\"\nother = 1\n\n[tui]\nx = 1\n"
        #expect(CodexProjects.trustLevel(in: text, project: "/a") == "untrusted")
        let edited = try CodexProjects.trusting("/a", in: text)
        #expect(edited == "[projects.\"/a\"]\ntrust_level = \"trusted\"\nother = 1\n\n[tui]\nx = 1\n")
        let bare = try CodexProjects.trusting("/b", in: "[projects.'/b']\nother = 1\n")
        #expect(bare == "[projects.'/b']\ntrust_level = \"trusted\"\nother = 1\n")
        #expect(CodexProjects.trustLevel(in: bare, project: "/b") == "trusted")
        #expect(throws: AgentFolderTrustError.self) {
            try CodexProjects.trusting("/c", in: "projects = { \"/a\" = { trust_level = \"trusted\" } }\n")
        }
        #expect(CodexProjects.basicString("/x \"q\"") == #""/x \"q\"""#)
    }

    @Test("Resolved paths keep /private, as the CLIs see them")
    func resolvedPrivate() {
        #expect(AgentFolderTrust.resolved(URL(fileURLWithPath: "/tmp")).path == "/private/tmp")
        #expect(AgentFolderTrust.keys(URL(fileURLWithPath: "/tmp")) == ["/tmp", "/private/tmp"])
    }

    @Test("Only Claude Code and Codex ask")
    func asks() {
        #expect(AgentFolderTrust.asks(.claude))
        #expect(AgentFolderTrust.asks(.codex))
        #expect(!AgentFolderTrust.asks(.shell))
    }
}

extension AgentFolderTrustTests {
    @Test("A projects folder covers a project in it unless a repository is in between")
    func parentCovers() throws {
        let root = try TestFixtures.temporaryDirectory("trust")
        let projects = try folder(root, "projects")
        #expect(AgentFolderTrust.parent(projects, covers: try folder(root, "projects/a")))
        #expect(!AgentFolderTrust.parent(projects, covers: projects))
        #expect(!AgentFolderTrust.parent(projects, covers: try folder(root, "elsewhere")))
        let repo = try folder(root, "projects/repo")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        #expect(!AgentFolderTrust.parent(projects, covers: try folder(root, "projects/repo/sub")))
    }
}

extension AgentFolderTrustTests {
    @Test("Claude: accepting Bypass Permissions mode merges into settings.json and keeps other keys")
    func claudeBypass() throws {
        let root = try TestFixtures.temporaryDirectory("trust")
        let trust = trust(root)
        #expect(trust.claudeSettings.path == root.appendingPathComponent("claude/settings.json").path)
        #expect(!trust.acceptsClaudeBypass)
        try FileManager.default.createDirectory(at: trust.claudeSettings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"model":"opus","skipDangerousModePermissionPrompt":false}"#.utf8).write(to: trust.claudeSettings)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: trust.claudeSettings.path)
        #expect(!trust.acceptsClaudeBypass)

        try trust.acceptClaudeBypass()
        #expect(trust.acceptsClaudeBypass)
        let settings = try #require(try AgentFolderTrust.readJSON(trust.claudeSettings))
        #expect(settings["model"] as? String == "opus")
        #expect(settings["skipDangerousModePermissionPrompt"] as? Bool == true)
        let permissions = try FileManager.default.attributesOfItem(atPath: trust.claudeSettings.path)[.posixPermissions] as? Int
        #expect(permissions == 0o644)
        let names = try FileManager.default.contentsOfDirectory(atPath: trust.claudeSettings.deletingLastPathComponent().path)
        #expect(names == ["settings.json"])
    }

    @Test("Claude: the older bypassPermissionsModeAccepted in .claude.json counts; settings.json that is not JSON is left alone")
    func claudeBypassLegacy() throws {
        let root = try TestFixtures.temporaryDirectory("trust")
        let trust = trust(root)
        try FileManager.default.createDirectory(at: trust.claudeConfig.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"bypassPermissionsModeAccepted":true}"#.utf8).write(to: trust.claudeConfig)
        #expect(trust.acceptsClaudeBypass)

        try Data("{ not json".utf8).write(to: trust.claudeSettings)
        #expect(throws: (any Error).self) { try trust.acceptClaudeBypass() }
        #expect(try String(contentsOf: trust.claudeSettings, encoding: .utf8) == "{ not json")
    }

    @Test("Claude: a fresh config gets settings.json with only the acceptance")
    func claudeBypassFresh() throws {
        let root = try TestFixtures.temporaryDirectory("trust")
        let trust = trust(root)
        try trust.acceptClaudeBypass()
        let settings = try #require(try AgentFolderTrust.readJSON(trust.claudeSettings))
        #expect(settings.count == 1)
        #expect(trust.acceptsClaudeBypass)
        let permissions = try FileManager.default.attributesOfItem(atPath: trust.claudeSettings.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }
}
