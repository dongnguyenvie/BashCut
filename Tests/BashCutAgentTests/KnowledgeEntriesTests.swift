import BashCutAgent
import Foundation
import Testing

struct KnowledgeEntriesTests {
    private func store(project: Bool = true) throws -> (store: AgentKnowledgeStore, root: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let projectFolder = root.appendingPathComponent("project", isDirectory: true)
        let user = root.appendingPathComponent("user", isDirectory: true)
        for url in [projectFolder, user] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        return (AgentKnowledgeStore(project: project ? projectFolder : nil, user: user), root)
    }

    private func source(_ agent: String = "claude", _ seconds: TimeInterval = 0) -> KnowledgeSource {
        KnowledgeSource(agent: agent, session: "s1", date: Date(timeIntervalSince1970: 1_800_000_000 + seconds))
    }

    @Test("Lessons are stored per scope as plain JSON, updated, removed and kept in history")
    func lessons() throws {
        let (store, root) = try store()
        defer { try? FileManager.default.removeItem(at: root) }
        let lesson = try store.addLesson(
            title: "Captions cover the face", symptom: "Bottom captions hide the chin in close-ups",
            cause: "Default lower-third position", fix: "Move captions up to 70 % in close-ups",
            tags: ["Captions", "captions", " framing "], scope: .project, source: source())
        try store.addLesson(title: "Sentence case", status: .proposed, scope: .user, source: source("codex", 1))

        #expect(lesson.id.hasPrefix("l-") && lesson.tags == ["captions", "framing"] && lesson.status == .active)
        let file = root.appendingPathComponent("project/.bashcut/knowledge/lessons.json")
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        #expect(json["version"] as? Int == 1 && (json["lessons"] as? [Any])?.count == 1)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("user/lessons.json").path))
        #expect(try store.lessons().map(\.scope) == [.project, .user])
        #expect(try store.lessons(.user).map(\.title) == ["Sentence case"])

        let updated = try store.updateLesson(
            lesson.id, LessonPatch(fix: "Captions at 70 %", status: .disabled), source: source("user", 2))
        #expect(updated.fix == "Captions at 70 %" && updated.status == .disabled && updated.source.agent == "claude")
        #expect(try store.lesson(lesson.id).updated == source("user", 2).date)
        #expect(throws: KnowledgeError.self) { try store.updateLesson(lesson.id, LessonPatch(), source: source()) }
        #expect(throws: KnowledgeError.self) { try store.updateLesson(lesson.id, LessonPatch(title: " "), source: source()) }

        try store.removeLesson(lesson.id, source: source("user", 3))
        #expect(throws: KnowledgeError.self) { try store.lesson(lesson.id) }
        let history = store.history(.project)
        #expect(history.map(\.action) == [.remove, .update, .add])
        #expect(history.first?.after == nil && history.first?.source.agent == "user")
        guard case .lesson(let before) = history[1].before else { Issue.record("No lesson before"); return }
        #expect(before.status == .active)
        #expect(store.history().count == 4 && store.history(limit: 2).count == 2)
    }

    @Test("Proposals are approved into active lessons or rejected out of the file")
    func proposals() throws {
        let (store, root) = try store()
        defer { try? FileManager.default.removeItem(at: root) }
        let keep = try store.addLesson(title: "Duck music −12 dB", status: .proposed, scope: .user, source: source())
        let drop = try store.addLesson(title: "Always use whip pans", status: .proposed, scope: .project, source: source())
        let active = try store.addLesson(title: "Hook in 2 s", scope: .project, source: source())
        #expect(try store.proposals().map(\.id) == [drop.id, keep.id])

        #expect(try store.approve(keep.id, source: source("user", 5)).status == .active)
        #expect(try store.reject(drop.id, source: source("user", 6)).id == drop.id)
        #expect(throws: KnowledgeError.self) { try store.approve(active.id, source: source()) }
        #expect(try store.proposals().isEmpty)
        #expect(try store.lessons().map(\.id) == [active.id, keep.id])
        #expect(store.history().prefix(2).map(\.action) == [.reject, .approve])
    }

    @Test("Preferences in either scope, facts only in the project; nil removes a key")
    func values() throws {
        let (store, root) = try store()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.setValue(.prefs, key: "pace", value: "fast", scope: .user, source: source())
        try store.setValue(.prefs, key: "pace", value: "calm", scope: .project, source: source())
        try store.setValue(.facts, key: "host", value: "Lan", scope: .project, source: source())
        #expect(throws: KnowledgeError.self) {
            try store.setValue(.facts, key: "host", value: "Lan", scope: .user, source: source())
        }
        #expect(try store.values(.prefs).map { "\($0.scope.rawValue):\($0.value)" } == ["project:calm", "user:fast"])
        #expect(try store.values(.facts).map(\.key) == ["host"])

        try store.setValue(.prefs, key: "pace", value: "medium", scope: .user, source: source("user", 1))
        #expect(try store.values(.prefs, scope: .user).map(\.value) == ["medium"])
        #expect(try store.setValue(.prefs, key: "pace", value: nil, scope: .project, source: source()) == nil)
        #expect(try store.values(.prefs, scope: .project).isEmpty)
        #expect(throws: KnowledgeError.self) {
            try store.setValue(.prefs, key: "missing", value: nil, scope: .user, source: source())
        }
        #expect(store.history(.user).map(\.action) == [.set, .set])
        #expect(store.history(.project).first?.action == .unset)
    }

    @Test("Without a project only the user's entries exist; a broken file is never overwritten")
    func noProjectAndBrokenFiles() throws {
        let (store, root) = try store(project: false)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: KnowledgeError.self) { try store.addLesson(title: "x", scope: .project, source: source()) }
        #expect(throws: KnowledgeError.self) {
            try store.setValue(.facts, key: "host", value: "Lan", scope: .project, source: source())
        }
        #expect(try store.lessons().isEmpty && store.values(.facts).isEmpty)

        let file = root.appendingPathComponent("user/lessons.json")
        try Data("{ not json".utf8).write(to: file)
        #expect(throws: KnowledgeError.self) { try store.addLesson(title: "x", scope: .user, source: source()) }
        #expect(try String(contentsOf: file, encoding: .utf8) == "{ not json")
    }

    @Test("Hand-written lessons with only an ID and title load with defaults")
    func handWritten() throws {
        let (store, root) = try store()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("project/.bashcut/knowledge", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"lessons": [{"id": "l-hand", "title": "Trim breaths"}]}"#.utf8)
            .write(to: folder.appendingPathComponent("lessons.json"))
        let lesson = try store.lesson("l-hand")
        #expect(lesson.status == .active && lesson.tags.isEmpty && lesson.source.agent == "unknown")
        try store.updateLesson("l-hand", LessonPatch(tags: ["audio"]), source: source())
        #expect(try store.lesson("l-hand").tags == ["audio"])
    }

    @Test("The session summary lists active lessons, winning preferences and facts, bounded and one line each")
    func summary() throws {
        let (store, root) = try store()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(store.summary().isEmpty && store.summary().text.contains("No lessons, preferences or facts yet."))

        let old = try store.addLesson(title: "Trim breaths", scope: .project, source: source())
        let new = try store.addLesson(
            title: "Captions\ncover the face", fix: String(repeating: "x", count: 500), scope: .project,
            source: source("claude", 5))
        let user = try store.addLesson(title: "Sentence case", scope: .user, source: source())
        try store.addLesson(title: "Maybe", status: .proposed, scope: .user, source: source())
        let off = try store.addLesson(title: "Old rule", scope: .project, source: source())
        try store.updateLesson(off.id, LessonPatch(status: .disabled), source: source())
        try store.setValue(.prefs, key: "pace", value: "fast", scope: .user, source: source())
        try store.setValue(.prefs, key: "pace", value: "calm", scope: .project, source: source())
        try store.setValue(.prefs, key: "music", value: "lofi", scope: .user, source: source())
        try store.setValue(.facts, key: "host", value: "Lan", scope: .project, source: source())

        let summary = store.summary()
        #expect(summary.lessons.map(\.id) == [new.id, old.id, user.id])
        #expect(summary.prefs.map { "\($0.key)=\($0.value)" } == ["pace=calm", "music=lofi"])
        #expect(summary.facts.map(\.key) == ["host"] && summary.proposals == 1 && summary.errors.isEmpty)
        let text = summary.text
        #expect(text.contains("- \(new.id) (project) Captions cover the face → " + String(repeating: "x", count: 239) + "…"))
        #expect(text.contains("- pace = calm (project)") && text.contains("1 proposed lesson(s)"))
        #expect(!text.contains("Old rule") && !text.contains("Maybe"))

        for index in 0..<KnowledgeSummary.lessonLimit {
            try store.addLesson(title: "Rule \(index)", scope: .user, source: source())
        }
        try Data("{ not json".utf8).write(to: root.appendingPathComponent("project/.bashcut/knowledge/facts.json"))
        let bounded = store.summary()
        #expect(bounded.lessons.count == KnowledgeSummary.lessonLimit && bounded.omittedLessons == 3)
        #expect(bounded.facts.isEmpty && bounded.errors.count == 1 && bounded.text.contains("… 3 more"))
    }
}
