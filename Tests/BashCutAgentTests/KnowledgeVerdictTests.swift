import BashCutAgent
import BashCutProject
import Foundation
import Testing

/// P3-I1: the user's verdicts on agents' changes, stored per project and counted by command.
struct KnowledgeVerdictTests {
    @Test("Verdicts append per project, read back oldest first and count per command and verdict")
    func ledger() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentKnowledgeStore(
            project: root.appendingPathComponent("project"), user: root.appendingPathComponent("user"))
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        try store.recordVerdict(KnowledgeVerdict(
            verdict: .undo, signal: .undo, subject: "timeline.apply", label: "Trim c2", agent: "claude", rev: 4,
            items: ["c2", "a1"], date: date))
        try store.recordVerdict(KnowledgeVerdict(
            verdict: .keep, signal: .dismiss, subject: "library.apply", label: "Apply look", agent: "claude", rev: 6,
            date: date.addingTimeInterval(5)))
        try store.recordVerdict(KnowledgeVerdict(
            verdict: .reject, signal: .scopeGuard, subject: nil, label: String(repeating: "x", count: 300),
            agent: "codex", date: date.addingTimeInterval(9)))
        let all = store.verdicts()
        #expect(all.map(\.verdict) == [.undo, .keep, .reject])
        #expect(all[0].items == ["a1", "c2"] && all[2].subject == "edit" && all[2].label.count == 120)

        let json = store.verdictsJSON(limit: 2).object
        #expect(json["total"] == .integer(3))
        #expect(json["counts"]?.object["timeline.apply"]?.object["undo"] == .integer(1))
        let rows = json["rows"]?.array ?? []
        #expect(rows.count == 2 && rows.first?.object["signal"] == .string("scope-guard"), "newest first")
        #expect(rows.first?.object["rev"] == nil && rows.last?.object["rev"] == .integer(6))
        #expect(store.verdictsJSON(verdict: .undo).object["total"] == .integer(1))
        #expect(store.verdictsJSON(subject: "library.apply").object["total"] == .integer(1))

        let unsaved = AgentKnowledgeStore(project: nil, user: root.appendingPathComponent("user"))
        #expect(unsaved.verdicts().isEmpty)
        #expect(throws: KnowledgeError.self) {
            try unsaved.recordVerdict(KnowledgeVerdict(verdict: .keep, signal: .dismiss, subject: nil, label: "x", agent: "a"))
        }
    }
}
