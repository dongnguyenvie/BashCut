import BashCutAgent
import BashCutProject
import Foundation
import Testing

struct KnowledgeMemoSplitTests {
    private func store() throws -> (store: AgentKnowledgeStore, root: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)
        let user = root.appendingPathComponent("user", isDirectory: true)
        for url in [project, user] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        return (AgentKnowledgeStore(project: project, user: user), root)
    }

    private func source(_ agent: String = "claude", _ seconds: TimeInterval = 0) -> KnowledgeSource {
        KnowledgeSource(agent: agent, session: "s1", date: Date(timeIntervalSince1970: 1_800_000_000 + seconds))
    }

    @Test("A memo with text is offered for the split until it is split or kept")
    func offer() throws {
        let (store, root) = try store()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(!store.memoNeedsSplit(.project))
        try store.writeMemo("Host: An\nCaptions: yellow, bottom", scope: .project)
        try store.writeMemo("  \n", scope: .user)
        #expect(store.memoNeedsSplit(.project))
        #expect(!store.memoNeedsSplit(.user))

        let before = store.signature()
        try store.keepMemo(.project, source: source("user"))
        #expect(store.signature() != before)
        #expect(!store.memoNeedsSplit(.project))
        #expect(store.memoSplitRecord(.project)?.outcome == .kept)
        #expect(throws: KnowledgeError.self) {
            try store.splitMemo(MemoSplit(facts: [.init(key: "host", value: "An")]), scope: .project, source: source())
        }

        try store.resetMemoSplit(.project)
        #expect(store.memoNeedsSplit(.project))
        #expect(!AgentKnowledgeStore(project: nil, user: root.appendingPathComponent("user")).memoNeedsSplit(.project))
    }

    @Test("Splitting queues proposals, skips what exists, keeps the memo and is recorded once")
    func split() throws {
        let (store, root) = try store()
        defer { try? FileManager.default.removeItem(at: root) }
        let memo = "Host: An\nPace: calm\nCaptions were too small on phones"
        try store.writeMemo(memo, scope: .project)
        try store.addLesson(title: "Check audio first", scope: .project, source: source("user"))
        try store.setValue(.facts, key: "city", value: "Hue", scope: .project, source: source("user"))
        let split = try JSONDecoder().decode(MemoSplit.self, from: Data("""
            {"lessons": [{"title": "Captions too small", "fix": "Use 7% of the height", "tags": ["captions"]},
                         {"title": "check audio first"}, {"title": "  "}],
             "prefs": [{"key": "pace", "value": "calm"}],
             "facts": [{"key": "host", "value": "An"}, {"key": "city", "value": "Hue"}]}
            """.utf8))

        let result = try store.splitMemo(split, scope: .project, source: source())
        #expect(result.lessons.map(\.title) == ["Captions too small"])
        #expect(result.lessons.first?.status == .proposed && result.lessons.first?.tags == ["captions", "memo"])
        #expect(result.values.map(\.key) == ["pace", "host"])
        #expect(result.values.allSatisfy { $0.scope == .project })
        #expect(result.skipped == ["lesson: check audio first", "facts: city"])
        #expect(try store.proposals().count == 1 && store.valueProposals().count == 2)
        #expect(store.memo(.project) == memo)
        let record = try #require(store.memoSplitRecord(.project))
        #expect(record.outcome == .split && record.source.agent == "claude" && record.facts == ["host"])
        #expect(!store.memoNeedsSplit(.project))
        #expect(throws: KnowledgeError.self) { try store.splitMemo(split, scope: .project, source: source()) }
    }

    @Test("Notes for every project split into lessons and preferences, never facts")
    func userScope() throws {
        let (store, root) = try store()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.writeMemo("Always calm music", scope: .user)
        #expect(throws: KnowledgeError.self) {
            try store.splitMemo(MemoSplit(facts: [.init(key: "host", value: "An")]), scope: .user, source: source())
        }
        #expect(store.memoNeedsSplit(.user))
        let result = try store.splitMemo(
            MemoSplit(prefs: [.init(key: "music", value: "calm")]), scope: .user, source: source())
        #expect(result.values.map(\.scope) == [.user])
        #expect(store.memoSplitRecord(.user)?.prefs == ["music"])
    }

    @Test("knowledge get reports the split state of each memo")
    func state() throws {
        let (store, root) = try store()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(store.memoSplitState(.project) == "none")
        try store.writeMemo("Host: An", scope: .project)
        try store.writeMemo("Calm music", scope: .user)
        #expect(store.memoSplitState(.project) == "pending" && store.memoSplitState(.user) == "pending")
        try store.splitMemo(MemoSplit(facts: [.init(key: "host", value: "An")]), scope: .project, source: source())
        try store.keepMemo(.user, source: source("user"))
        #expect(store.memoSplitState(.project) == "split" && store.memoSplitState(.user) == "kept")
    }

    @Test("Command entries decode from JSON; anything else fails with the expected shape")
    func json() throws {
        let split = try MemoSplit(json: .object([
            "lessons": .array([.object(["title": .string("Hook first"), "tags": .array([.string("pacing")])])]),
            "prefs": .array([.object(["key": .string("pace"), "value": .string("calm")])]),
        ]))
        #expect(split == MemoSplit(lessons: [.init(title: "Hook first", tags: ["pacing"])],
                                   prefs: [.init(key: "pace", value: "calm")]))
        #expect(try MemoSplit(json: .object([:])).isEmpty)
        for bad: JSONValue in [.array([]), .object(["lessons": .array([.object(["fix": .string("x")])])]),
                               .object(["prefs": .array([.object(["key": .string("pace")])])])] {
            #expect(throws: KnowledgeError.self, "\(bad)") { try MemoSplit(json: bad) }
        }
    }

    @Test("The hint and the request name the command, and the scope for notes for every project")
    func agentText() {
        #expect(AgentKnowledgeStore.splitHint(.project).contains("`bashcut knowledge split-memo <entries.json>`"))
        #expect(AgentKnowledgeStore.splitHint(.user).contains("split-memo <entries.json> --scope user`"))
        let project = AgentKnowledgeStore.splitRequest(.project)
        #expect(project.contains("the project memo") && project.contains("project facts")
            && project.contains("split-memo <file.json>`"))
        let user = AgentKnowledgeStore.splitRequest(.user)
        #expect(user.contains("the notes for every project") && !user.contains("project facts")
            && user.contains("--scope user"))
    }
}
