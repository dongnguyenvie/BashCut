import BashCutAgent
import Foundation
import Testing

struct KnowledgeHistoryTests {
    private func store() throws -> (store: AgentKnowledgeStore, root: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)
        let user = root.appendingPathComponent("user", isDirectory: true)
        for url in [project, user] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        return (AgentKnowledgeStore(project: project, user: user), root)
    }

    private func source(_ agent: String = "claude", _ seconds: TimeInterval = 0) -> KnowledgeSource {
        KnowledgeSource(agent: agent, date: Date(timeIntervalSince1970: 1_800_000_000 + seconds))
    }

    @Test("Reverting a lesson edit restores its fields; reverting the revert redoes it")
    func lessonEdit() throws {
        let (store, root) = try store()
        defer { try? FileManager.default.removeItem(at: root) }
        let lesson = try store.addLesson(title: "Hooks", fix: "Hook in 2 s", scope: .project, source: source())
        try store.updateLesson(lesson.id, LessonPatch(fix: "Hook in 5 s", tags: ["pacing"]), source: source("codex", 1))
        let edit = try #require(store.history(kind: .lesson, target: lesson.id).first)
        #expect(edit.action == .update && edit.diff.contains("-Fix: Hook in 2 s") && edit.diff.contains("+Fix: Hook in 5 s"))

        let revert = try store.revert(edit.id, source: source("user", 2))
        #expect(revert.action == .revert && revert.source.agent == "user")
        #expect(try store.lesson(lesson.id).fix == "Hook in 2 s" && store.lesson(lesson.id).tags.isEmpty)
        #expect(throws: KnowledgeError.self) { try store.revert(edit.id, source: source("user", 3)) }

        try store.revert(revert.id, source: source("user", 4))
        #expect(try store.lesson(lesson.id).fix == "Hook in 5 s")
    }

    @Test("Reverting an add removes the lesson and reverting a removal brings it back")
    func lessonAddRemove() throws {
        let (store, root) = try store()
        defer { try? FileManager.default.removeItem(at: root) }
        let lesson = try store.addLesson(title: "Sentence case", status: .proposed, scope: .user, source: source())
        try store.reject(lesson.id, source: source("user", 1))
        let reject = try #require(store.history(.user).first)
        #expect(reject.isRevertible)
        try store.revert(reject.id, source: source("user", 2))
        #expect(try store.lesson(lesson.id).status == .proposed)

        let add = try #require(store.history(.user, kind: .lesson).last)
        #expect(add.action == .add)
        try store.revert(add.id, source: source("user", 3))
        #expect(try store.lessons().isEmpty)
    }

    @Test("Values go back to their earlier value and source; a rejected value proposal cannot be reverted")
    func values() throws {
        let (store, root) = try store()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.setValue(.prefs, key: "pace", value: "fast", scope: .user, source: source())
        try store.setValue(.prefs, key: "pace", value: "slow", scope: .user, source: source("user", 1))
        try store.setValue(.facts, key: "host", value: "Lan", scope: .project, source: source("user", 2))
        let set = try #require(store.history(.user, target: "pace").first)
        try store.revert(set.id, source: source("user", 3))
        let pace = try #require(try store.values(.prefs).first)
        #expect(pace.value == "fast" && pace.source.agent == "claude")

        let fact = try #require(store.history(.project, kind: .facts).first)
        try store.revert(fact.id, source: source("user", 4))
        #expect(try store.values(.facts).isEmpty)

        let proposal = try store.proposeValue(.prefs, key: "music", value: "lofi", scope: .user, source: source("codex", 5))
        try store.rejectValue(proposal.id, source: source("user", 6))
        let reject = try #require(store.history(.user).first)
        #expect(!reject.isRevertible)
        #expect(throws: KnowledgeError.self) { try store.revert(reject.id, source: source("user", 7)) }
    }

    @Test("Memo and skill changes are recorded with their text and can be reverted")
    func memoAndSkills() throws {
        let (store, root) = try store()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.writeMemo("Fast cuts.", scope: .project, source: source())
        try store.writeMemo("Fast cuts.", scope: .project, source: source())
        try store.writeMemo("Fast cuts.\nWarm grade.", scope: .project, source: source("codex", 1))
        let memo = store.history(.project, kind: .memo)
        #expect(memo.count == 2 && memo[0].source.agent == "codex" && memo[0].diff == " Fast cuts.\n+Warm grade.")
        try store.revert(memo[0].id, source: source("user", 2))
        #expect(store.memo(.project) == "Fast cuts.")

        try store.writeSkill(named: "hook-first", text: "# Hook\n", source: source("claude", 3))
        try store.writeSkill(named: "hook-first", text: "# Hook v2\n", source: source("claude", 4))
        let skill = store.history(kind: .skill, target: "hook-first")
        #expect(skill.map(\.action) == [.update, .add])
        try store.revert(skill[0].id, source: source("user", 5))
        #expect(store.skillText("hook-first") == "# Hook\n")

        try store.revert(skill[1].id, source: source("user", 6))
        let project = root.appendingPathComponent("project")
        #expect(store.skills().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: project.appendingPathComponent(".claude/skills/hook-first").path))
        let removal = try #require(store.history(kind: .skill).first)
        #expect(removal.action == .revert && removal.after == nil)
        try store.revert(removal.id, source: source("user", 7))
        #expect(store.skillText("hook-first") == "# Hook\n" && store.skills().first?.claude == true)
    }

    @Test("Unified diffs fold long unchanged runs")
    func diff() {
        let before = (1...20).map { "line \($0)" }.joined(separator: "\n")
        let after = before.replacingOccurrences(of: "line 10\n", with: "line ten\n")
        #expect(KnowledgeDiff.unified(before, after) == """
            @@ 6 unchanged lines @@
             line 7
             line 8
             line 9
            -line 10
            +line ten
             line 11
             line 12
             line 13
            @@ 7 unchanged lines @@
            """)
        #expect(KnowledgeDiff.unified("", "a") == "+a" && KnowledgeDiff.unified("same", "same") == " same")
        #expect(KnowledgeDiff.unified("a\n", "a\nb\n") == " a\n+b")
    }
}
