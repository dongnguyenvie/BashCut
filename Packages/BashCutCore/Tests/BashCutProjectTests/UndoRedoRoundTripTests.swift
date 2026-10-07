import BashCutProjectFixtures
import Testing

@testable import BashCutProject

@Suite("Apply, undo and redo round trips")
struct UndoRedoRoundTripTests {
    /// Main clips `c1`/`c2`, an unlinked dialogue clip `snd`, a caption and a section marker.
    private static func base() throws -> Project {
        let project = try ProjectFixtures.twoClips("c1", "c2", sourceIn: (20, 140), name: "Round trip")
        var caption = Item(id: "cap", at: 0, duration: 30)
        caption["text"] = .string("Xin chào")
        return try project.applying(
            .group(
                label: "Extras", author: .user,
                ops: [
                    .insert(track: "a1", item: Item(id: "snd", media: "m", at: 0, duration: 60, sourceIn: 20)),
                    .insert(track: "t1", item: caption),
                    .upsertSection(id: "s0", label: "Intro", atFrame: 0),
                ])
        ).project
    }

    /// One valid edit per operation kind, each with a project that has what it needs (e.g. something to delete).
    private static func cases() throws -> [(operation: EditOperation, project: Project)] {
        let base = try base()
        let lut = ColorLUT(id: "look", name: "Look", path: "luts/look.cube", size: 2)
        let withTransition = try base.applying(
            .upsertTransition(id: "t", kind: "dissolve", from: "c1", to: "c2", duration: 12)).project
        let withLUT = try base.applying(.addColorLUT(lut)).project
        let operations: [EditOperation] = [
            .insert(track: "v1", item: Item(id: "c3", media: "m", at: 120, duration: 30)),
            .delete(item: "c1", ripple: true),
            .delete(item: "c2", ripple: false),
            .split(item: "c1", atFrame: 30, newID: "c1b"),
            .trim(item: "c1", edge: .end, toFrame: 40, ripple: false),
            .trim(item: "c2", edge: .start, toFrame: 70, ripple: true),
            .move(item: "c2", toTrack: "v2", atFrame: 200),
            .reorder(item: "c2", before: "c1"),
            .reorder(item: "c1", before: nil),
            .slip(item: "c1", sourceIn: 12),
            .roll(item: "c1", edge: .end, toFrame: 50),
            .setProperties(item: "c1", patch: ["opacity": .number(0.5), "future": .object(["x": .bool(true)])]),
            .setLinkedAudio(video: "c1", audio: "snd"),
            .addMedia(ProjectFixtures.media("m2", path: "b.mov")),
            .addTrack(track: Track(id: "v3", kind: "video", role: "overlay"), atIndex: 2),
            .deleteTrack(track: "v2"),
            .moveTrack(track: "v2", toIndex: 0),
            .setTrackProperties(track: "v2", patch: ["name": .string("B-roll")]),
            .setProjectProperties(patch: ["audio": .object(["targetLUFS": .integer(-14)])]),
            .setFormat(width: 1920, height: 1080),
            .setProviderPreference(capability: "voice.synthesize", provider: "acme.voice"),
            .setBeatGrid(media: "m", bpm: 120, frames: [0, 15], provenance: ["plugin": .string("p")]),
            .setMediaData(media: "m", patch: ["take": .integer(2), "verdict": .string("keep")]),
            .upsertSection(id: "s1", label: "Hook", atFrame: 30),
            .deleteSection(id: "s0"),
            .upsertTransition(id: "t", kind: "dissolve", from: "c1", to: "c2", duration: 12),
            .addColorLUT(lut),
            .group(label: "Batch", author: .codex, ops: [
                .delete(item: "cap", ripple: false), .setProperties(item: "c2", patch: ["opacity": .number(0.2)]),
            ]),
            .restore(Project(name: "Snapshot")),
        ]
        return operations.map { ($0, base) } + [
            (.deleteTransition(id: "t"), withTransition),
            (.deleteColorLUT(id: "look"), withLUT),
        ]
    }

    @Test("Every operation kind undoes to the original and redoes to the applied project")
    func everyOperation() throws {
        for (operation, project) in try Self.cases() {
            let result = try ProjectFixtures.undoRedo(operation, on: project)
            #expect(result.matches(original: project), "\(operation.json.object["op"]?.string ?? "?")")
            #expect(result.applied != project)
        }
    }

    @Test("The round trips cover every operation kind the codec knows")
    func coverage() throws {
        let covered = Set(try Self.cases().compactMap { $0.operation.json.object["op"]?.string })
        let known = Set(EditOperationCodecTests.samples.compactMap { $0.json.object["op"]?.string })
        #expect(known.subtracting(covered).isEmpty, "Missing round trips: \(known.subtracting(covered).sorted())")
    }
}
