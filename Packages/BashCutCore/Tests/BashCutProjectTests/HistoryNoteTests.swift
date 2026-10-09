import Foundation
import Testing

@testable import BashCutProject

@Suite("History notes")
struct HistoryNoteTests {
    private func caption(_ id: String, at frame: Int) -> Item {
        var item = Item(id: id, at: frame, duration: 30)
        item["text"] = .string(id)
        return item
    }

    @Test("A step keeps its why, evidence, date and revision through undo, redo and the journal")
    func keepsNote() throws {
        var history = ProjectHistory(project: Project(name: "Notes"))
        let note = EditNote(why: "Open on the line the plan quotes", evidence: ["review:hook-late", "m1 9.7–10.3s"])
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        try history.apply(.insert(track: "t1", item: caption("a", at: 0)), label: "Hook", author: .codex, note: note,
                          now: date)
        try history.apply(.insert(track: "t1", item: caption("b", at: 30)), label: "Plain", author: .user)
        let first = try #require(history.undoEntries.first)
        #expect(first.note == note && first.date == date && first.revision == 1)
        #expect(history.undoEntries.last?.note == nil)

        try history.undo()
        try history.undo()
        #expect(history.redoEntries.first?.note == nil && history.redoEntries.last?.note == note)
        try history.redo()
        #expect(history.undoEntries.last?.note == note && history.undoEntries.last?.revision == 1)

        let decoded = try JSONDecoder().decode(ProjectHistory.self, from: JSONEncoder().encode(history))
        #expect(decoded.undoEntries.last?.note == note && decoded.undoEntries.last?.date == date)
        #expect(decoded.redoEntries.last?.note == nil && decoded.redoEntries.last?.label == "Plain")
    }

    @Test("An empty note is not stored and a merged step keeps the first note")
    func emptyAndMerged() throws {
        var history = ProjectHistory(project: Project(name: "Notes"))
        try history.apply(.insert(track: "t1", item: caption("a", at: 0)), label: "Add", note: EditNote())
        #expect(history.undoEntries.last?.note == nil)
        let now = Date()
        try history.apply(.setProperties(item: "a", patch: ["opacity": .number(0.5)]), label: "Fade",
                          coalescingKey: "fade", note: EditNote(why: "first"), now: now)
        try history.apply(.setProperties(item: "a", patch: ["opacity": .number(0.4)]), label: "Fade",
                          coalescingKey: "fade", note: EditNote(why: "second"), now: now.addingTimeInterval(0.1))
        #expect(history.undoEntries.count == 2 && history.undoEntries.last?.note?.why == "first")
    }

    @Test("Journals written before notes still load without them")
    func oldJournal() throws {
        var history = ProjectHistory(project: Project(name: "Old"))
        try history.apply(.insert(track: "t1", item: caption("a", at: 0)), label: "Add")
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(history)) as? [String: Any])
        var entries = try #require(json["undoEntries"] as? [[String: Any]])
        for key in ["note", "date", "revision"] { entries[0].removeValue(forKey: key) }
        json["undoEntries"] = entries
        let decoded = try JSONDecoder().decode(ProjectHistory.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.undoEntries.count == 1 && decoded.undoEntries[0].note == nil && decoded.undoEntries[0].date == nil)
    }
}
