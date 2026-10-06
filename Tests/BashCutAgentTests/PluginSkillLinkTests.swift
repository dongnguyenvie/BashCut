import BashCutAgent
import BashCutPlugin
import Foundation
import Testing

/// Plugin skills reach agents (#377): linked into the project's agent folders and into folders BashCut owns, and
/// unlinked when the plugin stops providing them.
struct PluginSkillLinkTests {
    private func scratch() throws -> (root: URL, project: URL, store: AgentKnowledgeStore) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)
        let user = root.appendingPathComponent("user", isDirectory: true)
        for url in [project, user] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        return (root, project, AgentKnowledgeStore(project: project, user: user))
    }

    /// A plugin skill folder under `root/plugins/<plugin>/skills/<name>`.
    private func skill(_ name: String, plugin: String = "example.captions", in root: URL) throws -> PluginSkill {
        let folder = root.appendingPathComponent("plugins/\(plugin)/skills/\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "---\nname: \(name)\ndescription: Test.\n---\n".write(
            to: folder.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        return PluginSkill(pluginID: plugin, pluginName: "Captions", name: name, description: "Test.", folder: folder)
    }

    private func destination(_ url: URL) -> String? { try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) }

    @Test("Plugin skills are linked for Claude and Codex, kept out of project skills, and unlinked when gone")
    func projectLinks() throws {
        let (root, project, store) = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let transcribe = try skill("transcribe", in: root)
        let style = try skill("caption-style", in: root)
        try store.writeSkill(named: "food-cut", text: "# Food\n")

        let linked = try store.syncPluginSkills([transcribe, style])
        #expect(linked == ["example.captions--caption-style", "example.captions--transcribe"])
        for folder in [".claude/skills", ".agents/skills"] {
            let link = project.appendingPathComponent("\(folder)/example.captions--transcribe")
            #expect(destination(link) == transcribe.folder.path)
            #expect(FileManager.default.fileExists(atPath: link.appendingPathComponent("SKILL.md").path))
        }
        #expect(store.linkedPluginSkills() == linked)
        #expect(store.skills().map(\.name) == ["food-cut"])

        // The plugin stops shipping one skill (or is disabled): only BashCut's link goes.
        #expect(try store.syncPluginSkills([transcribe]) == ["example.captions--transcribe"])
        #expect(destination(project.appendingPathComponent(".claude/skills/example.captions--caption-style")) == nil)
        #expect(store.skills().first?.name == "food-cut")

        // Nothing left: the links and the ledger go; the project's own skill stays.
        #expect(try store.syncPluginSkills([]).isEmpty)
        #expect(destination(project.appendingPathComponent(".agents/skills/example.captions--transcribe")) == nil)
        #expect(!FileManager.default.fileExists(atPath: project.appendingPathComponent(".bashcut/plugin-skills.json").path))
        #expect(store.skills().first.map { $0.enabled && $0.claude && $0.codex } == true)
    }

    @Test("A folder that is not BashCut's link keeps its name")
    func foreignFolder() throws {
        let (root, project, store) = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let transcribe = try skill("transcribe", in: root)
        let own = project.appendingPathComponent(".claude/skills/example.captions--transcribe", isDirectory: true)
        try FileManager.default.createDirectory(at: own, withIntermediateDirectories: true)

        #expect(try store.syncPluginSkills([transcribe]) == ["example.captions--transcribe"])
        #expect(destination(own) == nil && FileManager.default.fileExists(atPath: own.path))
        #expect(destination(project.appendingPathComponent(".agents/skills/example.captions--transcribe")) != nil)
        try store.syncPluginSkills([])
        #expect(FileManager.default.fileExists(atPath: own.path))
    }

    @Test("Without a project nothing is linked")
    func noProject() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentKnowledgeStore(project: nil, user: root.appendingPathComponent("user"))
        #expect(try store.syncPluginSkills([try skill("transcribe", in: root)]).isEmpty)
    }

    @Test("Folders BashCut owns get plugin skills next to the kit's and lose them when they go")
    func ownedFolder() throws {
        let (root, _, _) = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("agent/.agents/skills", isDirectory: true)
        let transcribe = try skill("transcribe", in: root)
        try AgentKitInstall.syncSkills(of: nil, into: folder, plugins: [transcribe])
        #expect(destination(folder.appendingPathComponent("example.captions--transcribe")) == transcribe.folder.path)
        try AgentKitInstall.syncSkills(of: nil, into: folder)
        #expect(destination(folder.appendingPathComponent("example.captions--transcribe")) == nil)
    }
}
