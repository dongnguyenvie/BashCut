import BashCutAutomation
import BashCutProject
import Testing

struct TimelineChangesTests {
    private func caption(_ id: String, at frame: Int) -> Item {
        var item = Item(id: id, at: frame, duration: 30)
        item["text"] = .string(id)
        return item
    }

    @Test("The fingerprint follows the ops and base revision, not key order")
    func fingerprint() throws {
        let ops: [EditOperation] = [.insert(track: "t1", item: caption("a", at: 0))]
        let same = try EditFingerprint.of(ops, baseRevision: 4)
        #expect(same == (try EditFingerprint.of(ops, baseRevision: 4)) && same.count == 24)
        #expect(same != (try EditFingerprint.of(ops, baseRevision: 5)))
        #expect(same != (try EditFingerprint.of([.insert(track: "t1", item: caption("a", at: 1))], baseRevision: 4)))
        let wire: JSONValue = .array([.object([
            "op": .string("delete"), "item": .string("a"), "ripple": .bool(false),
        ])])
        let reordered: JSONValue = .array([.object([
            "ripple": .bool(false), "item": .string("a"), "op": .string("delete"),
        ])])
        #expect(try EditFingerprint.of(WireOperations.decode(wire), baseRevision: 1)
            == EditFingerprint.of(WireOperations.decode(reordered), baseRevision: 1))
    }

    @Test("Changes list the newest edits first with why, evidence, digest and the undone edits")
    func changes() throws {
        var history = ProjectHistory(project: Project(name: "Changes"))
        try history.apply(.insert(track: "t1", item: caption("a", at: 0)), label: "Title", author: .user)
        try history.apply(.insert(track: "t1", item: caption("b", at: 30)), label: "Hook", author: .codex,
                          note: EditNote(why: "Quote the plan's hook", evidence: ["plan:beat-1"]))
        try history.apply(.delete(item: "a", ripple: false), label: "Drop title", author: .claude)
        try history.undo()

        let all = TimelineChanges.json(history: history, limit: 10, isAgent: { $0 != .user }).object
        let edits = try #require(all["edits"]?.array).map(\.object)
        #expect(edits.map { $0["label"] } == [.string("Hook"), .string("Title")])
        #expect(edits[0]["step"] == .integer(1) && edits[0]["why"] == .string("Quote the plan's hook"))
        #expect(edits[0]["evidence"] == .array([.string("plan:beat-1")]) && edits[0]["rev"] == .integer(2))
        let digest = try #require(edits[0]["changes"]?.object)
        #expect(digest["counts"]?.object["added"] == .integer(1) && digest["text"] == .string("+ b on t1"))
        #expect(edits[1]["why"] == nil && edits[1]["changes"]?.object["text"] == .string("+ a on t1"))
        let undone = try #require(all["undone"]?.array.first?.object)
        #expect(undone["label"] == .string("Drop title") && undone["author"] == .string("claude"))
        #expect(undone["rev"] == .integer(3) && undone["at"]?.string != nil && undone["why"] == nil)
        #expect(all["counts"] == .object(["undoable": .integer(2), "redoable": .integer(1)]))

        let agents = TimelineChanges.json(history: history, limit: 10, author: "agent", isAgent: { $0 != .user }).object
        #expect(agents["edits"]?.array.count == 1)
        let one = TimelineChanges.json(history: history, limit: 1, isAgent: { _ in false }).object
        #expect(one["edits"]?.array.count == 1)
        #expect(TimelineChanges.json(history: history, limit: 5, author: "user", isAgent: { _ in false })
            .object["edits"]?.array.first?.object["step"] == .integer(2))
    }
}
