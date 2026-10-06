import BashCutProjectFixtures
import Testing
@testable import BashCutProject

struct SelectionEditsTests {
    /// Three 30-frame clips on an overlay layer at 0, 60 and 120, plus the two main-track clips.
    private func overlays() throws -> Project {
        let project = try ProjectFixtures.twoClips()
        let track = project.overflowTrack(from: try #require(project.track(id: "v1")))
        return try project.applying(.group(label: "Setup", author: .user, ops: [
            .addTrack(track: track, atIndex: 1),
            .insert(track: track.id, item: Item(id: "o1", media: "m", at: 0, duration: 30)),
            .insert(track: track.id, item: Item(id: "o2", media: "m", at: 60, duration: 30)),
            .insert(track: track.id, item: Item(id: "o3", media: "m", at: 120, duration: 30)),
        ])).project
    }

    private func item(_ id: String, in project: Project) -> Item? {
        project.tracks.flatMap(\.items).first { $0.id == id }
    }

    @Test("Deleting three clips is one undo step that restores all three")
    func bulkDelete() throws {
        let project = try overlays()
        let ops = SelectionEdits.delete(["o1", "o2", "o3"], ripple: false, in: project)
        #expect(ops.count == 3)
        var history = ProjectHistory(project: project)
        try history.apply(.group(label: "Delete", author: .user, ops: ops), label: "Delete", author: .user)
        #expect(["o1", "o2", "o3"].allSatisfy { item($0, in: history.project) == nil })
        try history.undo()
        #expect(["o1", "o2", "o3"].allSatisfy { item($0, in: history.project) != nil })
    }

    @Test("A linked pair counts once, so deleting both halves does not fail")
    func linkedPairOnce() throws {
        let project = try ProjectFixtures.linkedPair()
        let ops = SelectionEdits.delete(["v", "a"], ripple: true, in: project)
        #expect(ops.count == 1)
        let next = try project.applying(.group(label: "Delete", author: .user, ops: ops)).project
        #expect(next.tracks.allSatisfy { $0.items.isEmpty })
    }

    @Test("Mute toggles every selected clip, and unmutes when all are muted")
    func toggleMute() throws {
        var project = try overlays()
        project = try project.applying(.setProperties(item: "o1", patch: ["muted": .bool(true)])).project
        #expect(!SelectionEdits.allMuted(["o1", "o2"], in: project))
        project = try project.applying(.group(
            label: "Mute", author: .user, ops: SelectionEdits.toggleMute(["o1", "o2"], in: project))).project
        #expect(SelectionEdits.allMuted(["o1", "o2"], in: project))
        project = try project.applying(.group(
            label: "Mute", author: .user, ops: SelectionEdits.toggleMute(["o1", "o2"], in: project))).project
        #expect(item("o1", in: project)?["muted"] == .bool(false))
        #expect(item("o2", in: project)?["muted"] == .bool(false))
    }

    @Test("Moving selected clips keeps their offsets, even when one lands where another was")
    func shiftKeepsOffsets() throws {
        let project = try overlays()
        let ops = try SelectionEdits.shift(["o1", "o2", "o3"], by: 60, in: project)
        let next = try project.applying(.group(label: "Move", author: .user, ops: ops)).project
        let track = try #require(next.tracks.first { $0.items.contains { $0.id == "o1" } })
        #expect(track.items.sorted { $0.at < $1.at }.map(\.id) == ["o1", "o2", "o3"])
        #expect(["o1", "o2", "o3"].compactMap { item($0, in: next)?.at } == [60, 120, 180])
        #expect(throws: ProjectError.self) { try SelectionEdits.shift(["o1"], by: -1, in: project) }
    }

    @Test("A moved clip that would cover an unselected one spills onto a free layer")
    func shiftSpills() throws {
        let project = try overlays()
        let ops = try SelectionEdits.shift(["o1", "o2"], by: 60, in: project)
        let next = try project.applying(.group(label: "Move", author: .user, ops: ops)).project
        #expect(item("o2", in: next)?.at == 120)
        let o2Track = next.tracks.first { $0.items.contains { $0.id == "o2" } }
        let o3Track = next.tracks.first { $0.items.contains { $0.id == "o3" } }
        #expect(o2Track?.id != o3Track?.id)
    }

    @Test("Magnetic main-track clips stay put in a multi-move")
    func shiftSkipsMagnetic() throws {
        let project = try overlays()
        let ops = try SelectionEdits.shift(["left", "o3"], by: 30, in: project)
        let next = try project.applying(.group(label: "Move", author: .user, ops: ops)).project
        #expect(item("left", in: next)?.at == 0)
        #expect(item("o3", in: next)?.at == 150)
    }

    @Test("Shift-click selects the clips between the anchor and the target on the target's layer")
    func range() throws {
        let project = try overlays()
        #expect(SelectionEdits.range(from: "o1", to: "o3", in: project) == ["o1", "o2", "o3"])
        #expect(SelectionEdits.range(from: "o3", to: "o2", in: project) == ["o2", "o3"])
        #expect(SelectionEdits.range(from: "left", to: "o2", in: project) == ["o2"])
        #expect(SelectionEdits.all(in: project).count == 5)
    }

    @Test("Paste places copies at the playhead with new IDs and keeps linked pairs linked")
    func copyPaste() throws {
        let project = try ProjectFixtures.linkedPair()
        let clipboard = try #require(TimelineClipboard(copying: ["v"], from: project))
        #expect(clipboard.entries.count == 2)
        let pasted = try clipboard.paste(at: 90, in: project)
        let next = try project.applying(.group(label: "Paste", author: .user, ops: pasted.operations)).project
        #expect(pasted.ids.count == 2)
        let copies = pasted.ids.compactMap { item($0, in: next) }
        #expect(copies.allSatisfy { $0.at == 90 && $0.duration == 60 })
        #expect(copies.allSatisfy { $0.linkedItemID.map(pasted.ids.contains) == true })
        #expect(item("v", in: next)?.linkedItemID == "a")
    }

    @Test("Pasting over existing clips spills onto a free layer and keeps offsets")
    func pasteSpills() throws {
        let project = try overlays()
        let clipboard = try #require(TimelineClipboard(copying: ["o1", "o2"], from: project))
        let pasted = try clipboard.paste(at: 0, in: project)
        let next = try project.applying(.group(label: "Paste", author: .user, ops: pasted.operations)).project
        let copies = pasted.ids.compactMap { item($0, in: next) }
        #expect(copies.map(\.at) == [0, 60])
        #expect(item("o1", in: next)?.at == 0)
    }
}
