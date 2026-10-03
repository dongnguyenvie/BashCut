import BashCutProjectFixtures
import Foundation
import Testing

@testable import BashCutProject

@Suite("History journal")
struct HistoryJournalTests {
    /// Ten clips on the main layer, captions, a transition, then a mix of edits with two of them undone.
    private func history() throws -> ProjectHistory {
        var ops: [EditOperation] = [.addMedia(ProjectFixtures.media(frames: 6_000, fps: FrameRate(30, 1)))]
        for index in 0..<10 {
            ops.append(.insert(track: "v1", item: Item(id: "c\(index)", media: "m", at: index * 30, duration: 30)))
        }
        var caption = Item(id: "t0", at: 0, duration: 60)
        caption["text"] = .string("Xin chào")
        ops.append(.insert(track: "t1", item: caption))
        let project = try Project(name: "Journal", fps: FrameRate(30, 1)).applying(
            .group(label: "Setup", author: .user, ops: ops)).project
        var history = ProjectHistory(project: project)
        try history.apply(.setProperties(item: "c3", patch: ["opacity": .number(0.5)]), label: "Opacity")
        try history.apply(.upsertTransition(id: "x", kind: "dissolve", from: "c4", to: "c5", duration: 10), label: "Dissolve")
        try history.apply(.delete(item: "c1", ripple: true), label: "Ripple delete", author: .claude)
        try history.apply(.reorder(item: "c7", before: "c2"), label: "Reorder")
        try history.apply(.addTrack(track: Track(id: "v9", kind: "video", role: "overlay"), atIndex: 1), label: "Layer")
        try history.apply(.move(item: "t0", toTrack: "t1", atFrame: 90), label: "Move caption")
        try history.apply(.setProjectProperties(patch: ["note": .string("draft")]), label: "Note")
        let clip = try #require(history.project.tracks[0].items.first { $0.id == "c8" })
        try history.apply(.split(item: "c8", atFrame: clip.at + 10, newID: "c8b"), label: "Split")
        try history.undo()
        try history.undo()
        return history
    }

    private func roundTrip(_ history: ProjectHistory) throws -> ProjectHistory {
        try JSONDecoder().decode(ProjectHistory.self, from: JSONEncoder().encode(history))
    }

    private func sameEntries(_ lhs: [HistoryEntry], _ rhs: [HistoryEntry]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy {
            $0.label == $1.label && $0.author == $1.author && $0.operation == $1.operation
        }
    }

    @Test("A journal restores every undo and redo snapshot exactly")
    func roundTripsSnapshots() throws {
        var original = try history()
        var restored = try roundTrip(original)
        #expect(restored.project == original.project)
        #expect(original.undoEntries.count == 6 && original.redoEntries.count == 2)
        #expect(sameEntries(restored.undoEntries, original.undoEntries))
        #expect(sameEntries(restored.redoEntries, original.redoEntries))
        while original.canUndo {
            try original.undo()
            try restored.undo()
            #expect(restored.project == original.project)
        }
        while original.canRedo {
            try original.redo()
            try restored.redo()
            #expect(restored.project == original.project)
        }
    }

    @Test("Steps store only what changed")
    func storesDifferences() throws {
        let history = try history()
        let journal = try JSONEncoder().encode(history)
        let snapshots = try JSONEncoder().encode(Legacy(history))
        #expect(journal.count * 3 < snapshots.count, "journal \(journal.count) B, full snapshots \(snapshots.count) B")
    }

    /// The journal as it was written before deltas: every step a full `restore` snapshot.
    private struct Legacy: Encodable {
        let project: Project
        let undoEntries: [HistoryEntry]
        let redoEntries: [HistoryEntry]
        init(_ history: ProjectHistory) {
            project = history.project
            undoEntries = history.undoEntries
            redoEntries = history.redoEntries
        }
    }

    @Test("Journals with full snapshot operations still load")
    func readsFullSnapshotJournals() throws {
        let history = try history()
        let legacy = try JSONEncoder().encode(Legacy(history))
        let restored = try JSONDecoder().decode(ProjectHistory.self, from: legacy)
        #expect(restored.project == history.project)
        #expect(sameEntries(restored.undoEntries, history.undoEntries))
        #expect(sameEntries(restored.redoEntries, history.redoEntries))
    }

    @Test("Unknown fields and absent collections survive a delta")
    func deltaIsLossless() throws {
        var base = try ProjectFixtures.twoClips()
        var target = base
        target["x-custom"] = .object(["nested": .array([.integer(1), .null])])
        target["markers"] = nil
        target.tracks[0].items[1]["x-item"] = .string("kept")
        target.tracks[2]["x-layer"] = .bool(true)
        target.tracks.remove(at: 3)
        base["x-removed"] = .string("gone")
        let restored = try ProjectDelta.apply(ProjectDelta.encode(target, from: base), to: base)
        #expect(restored == target)
        #expect(restored.fields == target.fields)
    }

    @Test("A validated project is checked again once it changes")
    func validationIsRememberedOnlyUntilAChange() throws {
        var project = try ProjectFixtures.twoClips()
        try project.validate()
        project.tracks[0].items[1].at = 30  // now overlaps the first clip
        #expect(throws: ProjectError.self) { try project.validate() }
        var renamed = try ProjectFixtures.twoClips()
        renamed["schema"] = .string("bashcut.project/999")
        #expect(throws: ProjectError.self) { try renamed.validate() }
    }
}
