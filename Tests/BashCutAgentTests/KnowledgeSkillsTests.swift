import BashCutAgent
import Foundation
import Testing

struct KnowledgeSkillsTests {
    private func store() throws -> (store: AgentKnowledgeStore, root: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)
        let user = root.appendingPathComponent("user", isDirectory: true)
        for url in [project, user] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        return (AgentKnowledgeStore(project: project, user: user), root)
    }

    private let source = KnowledgeSource(agent: "user")

    @Test("Skills for every project live in the user folder, turn off with a marker and revert in user history")
    func userSkills() throws {
        let (store, root) = try store()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.writeSkill(named: "warm-grade", text: "# Warm\n", scope: .user, source: source)
        let skill = try #require(store.skills(.user).first)
        #expect(skill.enabled && skill.file.path.hasSuffix("user/skills/warm-grade/SKILL.md"))
        #expect(store.skills().isEmpty && store.skillText("warm-grade") == nil)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("project/.claude").path))

        try store.setSkillEnabled("warm-grade", false, scope: .user)
        #expect(store.skills(.user).first?.enabled == false)
        try store.setSkillEnabled("warm-grade", true, scope: .user)
        #expect(store.skills(.user).first?.enabled == true)

        try store.removeSkill(named: "warm-grade", scope: .user, source: source)
        #expect(store.skills(.user).isEmpty)
        let removal = try #require(store.history(.user, kind: .skill).first)
        #expect(removal.action == .remove && removal.scope == .user)
        try store.revert(removal.id, source: source)
        #expect(store.skillText("warm-grade", scope: .user) == "# Warm\n")
    }

    @Test("Turning a project skill off unlinks it for both agents; on links it again")
    func projectEnable() throws {
        let (store, root) = try store()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.writeSkill(named: "food-cut", text: "# Food\n", source: source)
        try store.setSkillEnabled("food-cut", false)
        let off = try #require(store.skills().first)
        #expect(!off.enabled && !off.claude && !off.codex)
        #expect(FileManager.default.fileExists(atPath: off.file.path))
        try store.setSkillEnabled("food-cut", true)
        #expect(store.skills().first.map { $0.enabled && $0.claude && $0.codex } == true)

        // A real folder in an agent's skills folder is not BashCut's link, so the skill cannot be turned off.
        let claudeCopy = root.appendingPathComponent("project/.claude/skills/own-skill", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeCopy, withIntermediateDirectories: true)
        try "# Own\n".write(to: claudeCopy.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        #expect(store.skills().first { $0.name == "own-skill" }?.enabled == true)
        #expect(throws: KnowledgeError.self) { try store.setSkillEnabled("own-skill", false) }
    }

    @Test("A kit change becomes a proposed lesson for every project with the diff")
    func kitProposal() throws {
        let (store, root) = try store()
        defer { try? FileManager.default.removeItem(at: root) }
        let lesson = try store.proposeKitChange(
            skill: "bashcut-beat-cut", before: "# Beat\nCut on beats.\n", after: "# Beat\nCut on downbeats.\n",
            summary: "Downbeats", reason: "Cuts felt late", source: KnowledgeSource(agent: "codex"))
        #expect(lesson.status == .proposed && lesson.scope == .user && lesson.tags == ["kit", "bashcut-beat-cut"])
        #expect(lesson.title == "Kit: bashcut-beat-cut — Downbeats")
        #expect(lesson.fix == " # Beat\n-Cut on beats.\n+Cut on downbeats.")
        #expect(throws: KnowledgeError.self) {
            try store.proposeKitChange(skill: "x", before: "a", after: "a", summary: "", source: source)
        }
    }

    @Test("Front matter gives the description, its triggers and the body")
    func frontMatter() {
        let front = SkillFrontMatter("""
            ---
            name: bashcut-beat-cut
            description: Give an edit rhythm. Triggers: "cắt theo nhịp", "beat".
            ---
            # Beat cut
            """)
        #expect(front.fields["name"] == "bashcut-beat-cut" && front.keys == ["name", "description"])
        #expect(front.summary == "Give an edit rhythm.")
        #expect(front.triggers == ["cắt theo nhịp", "beat"])
        #expect(front.body == "# Beat cut")
        #expect(SkillFrontMatter("# No front matter").body == "# No front matter")
    }
}
