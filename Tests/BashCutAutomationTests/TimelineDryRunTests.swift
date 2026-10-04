import BashCutAutomation
import BashCutProject
import Testing

struct TimelineDryRunTests {
    @Test("Dry-run predicts a batch while leaving the original project and revision unchanged")
    func batch() throws {
        let original = Project(name: "Preview")
        var caption = Item(id: "caption", at: 10, duration: 20)
        caption["text"] = .string("Xin chào")
        let operation = EditOperation.group(label: "Caption", author: .codex, ops: [
            .addTrack(track: Track(id: "new-text", kind: "text", role: "captions"), atIndex: 3),
            .insert(track: "new-text", item: caption)
        ])
        let result = try TimelineDryRun.evaluate(operation, on: original, baseRevision: original.revision).object
        let committed = try original.applying(operation).project
        #expect(original.revision == 0 && original.duration == 0)
        #expect(result["dryRun"] == .bool(true))
        #expect(result["rev"] == .integer(0))
        #expect(result["projectedRev"] == .integer(committed.revision))
        #expect(result["duration"] == .integer(committed.duration))
        #expect(result["changedItems"] == .array([.string("caption")]))
        #expect(result["addedTracks"] == .array([.string("new-text")]))
    }

    @Test("Dry-run rejects stale, locked and invalid edits using the same validation as commit")
    func validation() throws {
        var caption = Item(id: "caption", at: 0, duration: 20)
        caption["text"] = .string("Caption")
        let original = try Project(name: "Validation").applying(.insert(track: "t1", item: caption)).project
        let edit = EditOperation.delete(item: "caption", ripple: false)
        #expect(throws: ProjectError.self) { try TimelineDryRun.evaluate(edit, on: original, baseRevision: 0) }
        let locked = try original.applying(.setTrackProperties(track: "t1", patch: ["locked": .bool(true)])).project
        #expect(throws: ProjectError.self) { try TimelineDryRun.evaluate(edit, on: locked, baseRevision: locked.revision) }
        #expect(throws: ProjectError.self) {
            try TimelineDryRun.evaluate(.delete(item: "missing", ripple: false), on: original, baseRevision: original.revision)
        }
        let result = try TimelineDryRun.evaluate(edit, on: original, baseRevision: original.revision).object
        #expect(result["changedItems"] == .array([.string("caption")]))
        #expect(result["duration"] == .integer(0))
        #expect(original.duration == 20)
    }
}
