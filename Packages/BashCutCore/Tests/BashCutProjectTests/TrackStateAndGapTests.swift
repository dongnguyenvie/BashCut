import BashCutProjectFixtures
import Testing

@testable import BashCutProject

@Suite("Layer switches and gaps")
struct TrackStateAndGapTests {
    /// Main clips at 0–60 and 90–150 (a 30-frame gap), with linked sound on the second.
    private func gapped() throws -> Project {
        var video = Item(id: "b", media: "m", at: 90, duration: 60)
        video.fields["linkedAudio"] = .string("b-audio")
        var audio = Item(id: "b-audio", media: "m", at: 90, duration: 60)
        audio.fields["linkedVideo"] = .string("b")
        return try Project(name: "Gaps", fps: FrameRate(30, 1)).applying(
            .group(
                label: "Setup", author: .user,
                ops: [
                    .addMedia(ProjectFixtures.media(kind: "video", hasAudio: true)),
                    .insert(track: "v1", item: Item(id: "a", media: "m", at: 0, duration: 60)),
                    .insert(track: "a1", item: audio), .insert(track: "v1", item: video),
                ])
        ).project
    }

    @Test("Gaps are the empty ranges before and between items")
    func gaps() throws {
        let project = try gapped()
        #expect(project.tracks[0].gaps == [60..<90])
        #expect(project.tracks.first { $0.id == "a1" }?.gaps == [0..<90])
        #expect(try project.gap(on: "v1", containing: 75) == 60..<90)
        #expect(throws: ProjectError.self) { try project.gap(on: "v1", containing: 10) }
    }

    @Test("Closing a gap moves later clips left with their linked sound, in one undoable edit")
    func closeGap() throws {
        let project = try gapped()
        let result = try ProjectFixtures.undoRedo(project.closingGap(on: "v1", containing: 70), on: project)
        let items = result.applied.tracks.flatMap(\.items)
        #expect(items.first { $0.id == "b" }?.at == 60)
        #expect(items.first { $0.id == "b-audio" }?.at == 60)
        #expect(result.applied.tracks[0].gaps.isEmpty)
        #expect(result.matches(original: project))
    }

    @Test("A locked layer refuses edits to its items until unlocked; undo still works")
    func lock() throws {
        var project = try gapped()
        project = try project.applying(.setTrackProperties(track: "v1", patch: ["locked": .bool(true)])).project
        #expect(project.tracks[0].isLocked)
        #expect(throws: ProjectError.self) { try project.applying(.delete(item: "a", ripple: true)) }
        #expect(throws: ProjectError.self) { try project.applying(.setProperties(item: "a", patch: ["opacity": .number(0.5)])) }
        // Linked sound would drag the locked picture along.
        #expect(throws: ProjectError.self) { try project.applying(.move(item: "b-audio", toTrack: "a1", atFrame: 200)) }
        #expect(throws: ProjectError.self) { try project.applying(.insert(track: "v1", item: Item(id: "c", media: "m", at: 150, duration: 10))) }
        // Other layers stay editable, and unlocking is always allowed.
        _ = try project.applying(.upsertSection(id: "s", label: "Hook", atFrame: 0))
        let unlocked = try project.applying(.setTrackProperties(track: "v1", patch: ["locked": .bool(false)])).project
        _ = try unlocked.applying(.delete(item: "a", ripple: false))
        // A snapshot restore (undo) is exempt.
        _ = try project.applying(.restore(try gapped()))
    }

    @Test("Hide is for visual layers, mute for audio layers, and all switches are booleans")
    func validation() throws {
        let project = try gapped()
        _ = try project.applying(.setTrackProperties(track: "v1", patch: ["hidden": .bool(true)]))
        _ = try project.applying(.setTrackProperties(track: "a1", patch: ["muted": .bool(true)]))
        #expect(throws: ProjectError.self) {
            try project.applying(.setTrackProperties(track: "a1", patch: ["hidden": .bool(true)]))
        }
        #expect(throws: ProjectError.self) {
            try project.applying(.setTrackProperties(track: "v1", patch: ["muted": .bool(true)]))
        }
        #expect(throws: ProjectError.self) {
            try project.applying(.setTrackProperties(track: "v1", patch: ["locked": .string("yes")]))
        }
    }
}
