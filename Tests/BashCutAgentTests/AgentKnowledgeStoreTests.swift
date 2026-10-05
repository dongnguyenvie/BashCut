import BashCutAgent
import Foundation
import Testing

struct AgentKnowledgeStoreTests {
    private func folders() throws -> (root: URL, project: URL, user: URL, workspace: URL, home: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let urls = ["project", "user", "workspace", "home"].map { root.appendingPathComponent($0, isDirectory: true) }
        for url in urls { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        return (root, urls[0], urls[1], urls[2], urls[3])
    }

    @Test("Project knowledge stays in the project; skills link inside it, never in the workspace or home")
    func projectKnowledge() throws {
        let folders = try folders()
        defer { try? FileManager.default.removeItem(at: folders.root) }
        let store = AgentKnowledgeStore(
            project: folders.project, user: folders.user, legacyFolders: [folders.workspace, folders.home])
        try store.writeMemo("Bếp nhà Lan, quay 4K.", scope: .project)
        try store.writeMemo("Captions in sentence case.", scope: .user)
        try store.writeSkill(named: "food-cut", text: "# Food cut\n")

        #expect(store.memo(.project) == "Bếp nhà Lan, quay 4K.")
        #expect(FileManager.default.fileExists(atPath: folders.project.appendingPathComponent(".bashcut/agent-memory.md").path))
        #expect(store.memo(.user) == "Captions in sentence case.")
        #expect(FileManager.default.fileExists(atPath: folders.user.appendingPathComponent("agent-memory.md").path))
        let skill = try #require(store.skills().first)
        #expect(skill.name == "food-cut" && skill.claude && skill.codex)
        let link = folders.project.appendingPathComponent(".claude/skills/food-cut")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == "../../.bashcut/skills/food-cut")
        for folder in [folders.workspace, folders.home] {
            #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
        }

        try store.writeSkill(named: "food-cut", text: "# Food cut v2\n")
        #expect(try String(contentsOf: skill.url.appendingPathComponent("SKILL.md"), encoding: .utf8) == "# Food cut v2\n")
        #expect(throws: KnowledgeError.self) { try store.writeSkill(named: "Food Cut!", text: "x") }
    }

    @Test("Without a saved project, project writes are refused and the notes for every project still work")
    func noProject() throws {
        let folders = try folders()
        defer { try? FileManager.default.removeItem(at: folders.root) }
        let store = AgentKnowledgeStore(project: nil, user: folders.user, legacyFolders: [folders.home])
        #expect(throws: KnowledgeError.self) { try store.writeMemo("x", scope: .project) }
        #expect(throws: KnowledgeError.self) { try store.writeSkill(named: "cut", text: "x") }
        #expect(store.skills().isEmpty)
        try store.writeMemo("Short hooks.", scope: .user)
        #expect(store.memo(.user) == "Short hooks.")
        #expect(try FileManager.default.contentsOfDirectory(atPath: folders.home.path).isEmpty)
    }

    @Test("An older workspace memo is offered once and moved into the chosen memo")
    func migration() throws {
        let folders = try folders()
        defer { try? FileManager.default.removeItem(at: folders.root) }
        let old = folders.workspace.appendingPathComponent(".bashcut/agent-memory.md")
        try FileManager.default.createDirectory(at: old.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "Music under voice at -18 LUFS.\n".write(to: old, atomically: true, encoding: .utf8)
        let store = AgentKnowledgeStore(
            project: folders.project, user: folders.user, legacyFolders: [folders.workspace, folders.home])
        try store.writeMemo("Fast cuts.", scope: .user)

        let legacy = try #require(store.legacyMemo())
        #expect(legacy.url.standardizedFileURL == old.standardizedFileURL)
        let text = try store.migrate(legacy, to: .user)
        #expect(text == "Fast cuts.\n\nMusic under voice at -18 LUFS.\n")
        #expect(store.memo(.user) == text)
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(
            atPath: folders.workspace.appendingPathComponent(".bashcut/agent-memory.migrated.md").path))
        #expect(store.legacyMemo() == nil)
    }

    @Test("A workspace that is the project folder is not treated as an older memo")
    func workspaceIsProject() throws {
        let folders = try folders()
        defer { try? FileManager.default.removeItem(at: folders.root) }
        let store = AgentKnowledgeStore(project: folders.project, user: folders.user, legacyFolders: [folders.project])
        try store.writeMemo("Project facts.", scope: .project)
        #expect(store.legacyMemo() == nil)
    }
}
