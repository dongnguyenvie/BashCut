import BashCutAgent
import Foundation
import Testing

struct KnowledgeFilterTests {
    private func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: 1_800_000_000 + seconds) }

    private func lesson(
        _ id: String, _ seconds: TimeInterval, status: LessonStatus = .active, scope: KnowledgeScope = .project,
        tags: [String] = [], evidence: String = ""
    ) -> KnowledgeLesson {
        KnowledgeLesson(
            id: id, title: "Lesson \(id)", fix: "fix \(id)", evidence: evidence, tags: tags, status: status,
            source: KnowledgeSource(agent: "claude", date: date(seconds)), scope: scope)
    }

    @Test("Lessons filter by scope, status, tag and text, newest or oldest first")
    func lessons() {
        let lessons = [
            lesson("a", 10, tags: ["captions"]),
            lesson("b", 30, status: .proposed, scope: .user, tags: ["audio"]),
            lesson("c", 20, status: .disabled, evidence: "Frame 120 shows the chin"),
            lesson("d", 20, tags: ["captions"]),
        ]
        #expect(KnowledgeFilter().apply(lessons).map(\.id) == ["b", "c", "d", "a"])
        #expect(KnowledgeFilter(sort: .oldest).apply(lessons).map(\.id) == ["a", "c", "d", "b"])
        #expect(KnowledgeFilter(scope: .user).apply(lessons).map(\.id) == ["b"])
        #expect(KnowledgeFilter(status: .active).apply(lessons).map(\.id) == ["d", "a"])
        #expect(KnowledgeFilter(tag: "Captions").apply(lessons).map(\.id) == ["d", "a"])
        #expect(KnowledgeFilter(query: " CHIN ").apply(lessons).map(\.id) == ["c"])
        #expect(KnowledgeFilter(query: "audio").apply(lessons).map(\.id) == ["b"])
        #expect(KnowledgeFilter.tags(lessons) == ["audio", "captions"])
    }

    @Test("Values filter by scope and by text in the key or value")
    func values() {
        let values = [
            KnowledgeValue(key: "pace", value: "Fast cuts", source: KnowledgeSource(agent: "user", date: date(1))),
            KnowledgeValue(key: "voice", value: "Calm", source: KnowledgeSource(agent: "codex", date: date(5)),
                           scope: .user),
        ]
        #expect(KnowledgeFilter().apply(values).map(\.key) == ["voice", "pace"])
        #expect(KnowledgeFilter(query: "fast").apply(values).map(\.key) == ["pace"])
        #expect(KnowledgeFilter(scope: .user).apply(values).map(\.key) == ["voice"])
    }

    @Test("Entries are new only when changed after a previous visit")
    func newSinceVisit() {
        #expect(!KnowledgeFilter.isNew(date(10), since: nil))
        #expect(KnowledgeFilter.isNew(date(10), since: date(5)))
        #expect(!KnowledgeFilter.isNew(date(5), since: date(5)))
    }

    @Test("The store's signature changes when a knowledge file is written")
    func signature() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("project", isDirectory: true)
        let user = root.appendingPathComponent("user", isDirectory: true)
        for url in [project, user] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        let store = AgentKnowledgeStore(project: project, user: user)
        let empty = store.signature()
        try store.setValue(.facts, key: "host", value: "Lan", scope: .project,
                           source: KnowledgeSource(agent: "user"))
        let one = store.signature()
        #expect(one != empty)
        #expect(store.signature() == one)
    }
}
