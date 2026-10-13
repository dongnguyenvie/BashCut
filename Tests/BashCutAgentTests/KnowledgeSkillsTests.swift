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

/// `skills get --section`: a skill split at its `## ` headings.
struct SkillSectionsTests {
    @Test("Sections split at ## headings outside code fences; the front matter is left out")
    func sections() {
        let text = "---\nname: x\ndescription: y\n---\n# Title\nintro\n## Plan data\nrows\n```sh\n## not a heading\n```\n"
            + "## Review profile\nranges\n"
        let sections = SkillFrontMatter.sections(text)
        #expect(sections.map(\.heading) == ["Intro", "Plan data", "Review profile"])
        #expect(sections[1].text.contains("## not a heading") && !sections[0].text.contains("name: x"))
        #expect(sections[2].text == "## Review profile\nranges\n\n")
    }
}

/// The Knowledge › Skills preview (#126, #127) and the new skill name field (#128).
struct SkillMarkdownTests {
    @Test("Numbered items keep their number and take indented continuation lines")
    func numbered() {
        let blocks = SkillMarkdown.blocks("1. Survey\n   the footage\n2. Rough cut\n\n2026 was a year.\n10. Ten")
        #expect(blocks == [
            .numbered("1", "Survey the footage"), .numbered("2", "Rough cut"), .paragraph("2026 was a year."),
            .numbered("10", "Ten"),
        ])
    }

    @Test("Quote lines join into one block; a body rule is a divider, front matter is not")
    func quotesAndRules() {
        let text = "---\nname: x\n---\n> first line\n> second line\n\n---\n## Next\n- a\n* b\n***"
        let blocks = SkillMarkdown.blocks(SkillFrontMatter(text).body)
        #expect(blocks == [
            .quote("first line\nsecond line"), .rule, .heading(2, "Next"), .bullet("a"), .bullet("b"), .rule,
        ])
        #expect(SkillMarkdown.blocks("| a |\n| b |") == [.code("| a |\n| b |")])
        #expect(SkillMarkdown.blocks("```\n> not a quote\n```") == [.code("> not a quote")])
    }

    @Test("A skill name is checked as it is typed")
    func names() {
        #expect(!AgentKnowledgeStore.isValidSkillName("Hook First!"))
        #expect(AgentKnowledgeStore.isValidSkillName("hook-first"))
        #expect(!AgentKnowledgeStore.isValidSkillName("") && !AgentKnowledgeStore.isValidSkillName("hook--first"))
    }
}

/// `skills get` finds a kit skill by the names agents see it by (Codex live run, 2026-10-13: `bc:review` failed).
struct KitSkillNameTests {
    @Test("bc:review and bc-review name the kit skill review; other names stay")
    func kitNames() {
        #expect(AgentKnowledgeStore.kitSkillName("bc:review") == "review")
        #expect(AgentKnowledgeStore.kitSkillName("bc-edit-workflow") == "edit-workflow")
        #expect(AgentKnowledgeStore.kitSkillName("review") == "review")
        #expect(AgentKnowledgeStore.kitSkillName("bc:") == "bc:")
        #expect(AgentKnowledgeStore.kitSkillName("bashcut.vlog:plan") == "bashcut.vlog:plan")
    }
}
