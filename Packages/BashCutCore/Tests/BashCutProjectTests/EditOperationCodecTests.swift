import Foundation
import Testing

@testable import BashCutProject

@Suite("Edit operation codec and history")
struct EditOperationCodecTests {
    /// One sample of every case (the exhaustive `json` switch forces new cases into the codec; add a sample here too).
    static let samples: [EditOperation] = [
        .insert(track: "v1", item: Item(id: "c1", media: "m1", at: 0, duration: 30)),
        .delete(item: "c1", ripple: true),
        .split(item: "c1", atFrame: 10, newID: "c1b"),
        .trim(item: "c1", edge: .end, toFrame: 20, ripple: false),
        .move(item: "c1", toTrack: "v2", atFrame: 5),
        .reorder(item: "c1", before: "c2"),
        .reorder(item: "c1", before: nil),
        .slip(item: "c1", sourceIn: 12),
        .roll(item: "c1", edge: .start, toFrame: 3),
        .setProperties(item: "c1", patch: ["opacity": .number(0.5), "future": .object(["x": .bool(true)])]),
        .setLinkedAudio(video: "c1", audio: "a1"),
        .setLinkedAudio(video: "c1", audio: nil),
        .addMedia(Media(fields: ["id": .string("m2"), "path": .string("b.mov")])),
        .addTrack(track: Track(id: "v3", kind: "video", role: "overlay"), atIndex: 2),
        .deleteTrack(track: "v3"),
        .moveTrack(track: "v2", toIndex: 0),
        .setTrackProperties(track: "v2", patch: ["name": .string("B-roll")]),
        .setProjectProperties(patch: ["audio": .object(["targetLUFS": .integer(-14)])]),
        .setProviderPreference(capability: "voice.synthesize", provider: "acme.voice"),
        .setProviderPreference(capability: "voice.synthesize", provider: nil),
        .setBeatGrid(media: "m1", bpm: 120, frames: [0, 15], provenance: ["plugin": .string("p")]),
        .setBeatGrid(media: "m1", bpm: 90, frames: [0], provenance: nil),
        .upsertSection(id: "s1", label: "Hook", atFrame: 0),
        .deleteSection(id: "s1"),
        .upsertTransition(id: "t", kind: "dissolve", from: "c1", to: "c2", duration: 12),
        .deleteTransition(id: "t"),
        .addColorLUT(ColorLUT(fields: ["id": .string("look"), "path": .string("luts/look.cube")])),
        .deleteColorLUT(id: "look"),
        .group(label: "Batch", author: .codex, ops: [.delete(item: "c1", ripple: false)]),
        .restore(Project(name: "Snapshot")),
    ]

    @Test("Every operation round-trips through the op-keyed JSON and Codable forms")
    func roundTrip() throws {
        for operation in Self.samples {
            #expect(try EditOperation(json: operation.json, allowInternal: true) == operation)
            let data = try JSONEncoder().encode(operation)
            #expect(try JSONDecoder().decode(EditOperation.self, from: data) == operation)
            #expect(operation.json.object["op"]?.string != nil)
        }
    }

    @Test("Agents cannot submit internal group or restore operations")
    func internalOperationsRejected() {
        for operation in [Self.samples[Self.samples.count - 2], Self.samples[Self.samples.count - 1]] {
            #expect(throws: ProjectError.self) { try EditOperation(json: operation.json) }
        }
        #expect(throws: ProjectError.invalid("atFrame must be an integer frame")) {
            try EditOperation(json: .object(["op": .string("split"), "item": .string("c"), "atFrame": .integer(-1)]))
        }
    }

    @Test("History survives the journal round trip and exposes snapshots through before")
    func journal() throws {
        var history = ProjectHistory(project: Project(name: "Journal"))
        try history.apply(.upsertSection(id: "s1", label: "Hook", atFrame: 0), label: "Section")
        try history.apply(.deleteSection(id: "s1"), label: "Remove")
        try history.undo()
        let restored = try JSONDecoder().decode(ProjectHistory.self, from: JSONEncoder().encode(history))
        #expect(restored.project == history.project)
        #expect(restored.undoEntries.map(\.label) == ["Section"])
        #expect(restored.redoEntries.map(\.label) == ["Remove"])
        #expect(restored.lastUndo?.before?.sectionMarkers.isEmpty == true)
    }

    @Test("Undo depth is capped and drops the oldest steps")
    func depthCap() throws {
        var history = ProjectHistory(project: Project(name: "Cap"))
        for index in 0..<(ProjectHistory.maximumDepth + 5) {
            try history.apply(.setProjectProperties(patch: ["note": .integer(index)]), label: "Step \(index)")
        }
        #expect(history.undoEntries.count == ProjectHistory.maximumDepth)
        #expect(history.undoEntries.first?.label == "Step 5")
    }

    @Test("Tracks resolve by role and placement links sound to the dialogue track")
    func trackRoles() throws {
        var project = Project(name: "Roles")
        #expect(project.track(role: TrackRole.voiceover)?.id == "a2")
        #expect(project.insertionFrame(trackID: "a3", playhead: 42) == 42)
        project = try project.applying(.addTrack(track: Track(id: "vo-2", kind: "audio", role: "voiceover"), atIndex: 3))
            .project
        #expect(project.track(role: TrackRole.voiceover)?.id == "vo-2")
        project = try project.applying(.deleteTrack(track: "t1")).project
        #expect(throws: ProjectError.invalid("Add a captions track first")) {
            try project.requireTrack(role: TrackRole.captions)
        }
        let media = Media(fields: [
            "id": .string("m1"), "path": .string("a.mov"), "kind": .string("video"), "fps": FrameRate().json,
            "frames": .integer(300), "hasAudio": .bool(true),
        ])
        let operations = try project.placementOperations(media: media, trackID: "v1", at: 0, duration: 30, itemID: "x")
        #expect(operations.count == 2)
        guard case .insert(let dialogue, let audio) = operations[0], case .insert(let main, let video) = operations[1]
        else { Issue.record("Expected two inserts"); return }
        #expect(dialogue == "a1" && main == "v1")
        #expect(video["linkedAudio"] == .string("x-audio") && audio["linkedVideo"] == .string("x"))
    }
}
