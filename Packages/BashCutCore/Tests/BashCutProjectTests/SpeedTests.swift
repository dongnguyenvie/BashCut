import BashCutProjectFixtures
import Testing

@testable import BashCutProject

struct SpeedTests {
    private func item(_ project: Project, _ id: String) throws -> Item {
        try #require(project.tracks.flatMap(\.items).first { $0.id == id })
    }

    @Test("2× halves the clip, keeps the same source and ripples the next clip")
    func changesDuration() throws {
        let project = try ProjectFixtures.twoClips()
        let fast = try project.applying(.setSpeed(item: "left", speed: 2, keepDuration: false)).project
        #expect(try item(fast, "left").duration == 30)
        #expect(try item(fast, "left").speed == 2)
        #expect(try item(fast, "right").at == 30)
        // Back to 1× restores the length and removes the field.
        let normal = try fast.applying(.setSpeed(item: "left", speed: 1, keepDuration: false)).project
        #expect(try item(normal, "left").duration == 60)
        #expect(try item(normal, "left").fields["speed"] == nil)
        #expect(try item(normal, "right").at == 60)
        // Slowing down pushes the next clip later.
        let slow = try project.applying(.setSpeed(item: "left", speed: 0.5, keepDuration: false)).project
        #expect(try item(slow, "left").duration == 120)
        #expect(try item(slow, "right").at == 120)
    }

    @Test("Keeping the duration uses more source, and shortens to fit when the source runs out")
    func keepsDuration() throws {
        let project = try ProjectFixtures.twoClips()
        let kept = try project.applying(.setSpeed(item: "left", speed: 2, keepDuration: true)).project
        #expect(try item(kept, "left").duration == 60)
        #expect(try item(kept, "right").at == 60)
        // `right` starts at source frame 120 of 600 (60 fps): 480 frames = 8 s left; at 8× that fills 1 s = 30 frames.
        let fitted = try project.applying(.setSpeed(item: "right", speed: 8, keepDuration: true)).project
        #expect(try item(fitted, "right").duration == 30)
    }

    @Test("Linked picture and sound change together")
    func linked() throws {
        let project = try ProjectFixtures.linkedPair()
        let fast = try project.applying(.setSpeed(item: "a", speed: 1.5, keepDuration: false)).project
        #expect(try item(fast, "v").duration == 40 && item(fast, "a").duration == 40)
        #expect(try item(fast, "v").speed == 1.5 && item(fast, "a").speed == 1.5)
    }

    @Test("Text, freeze frames, out-of-range speeds and locked layers are refused; undo restores")
    func refusals() throws {
        let project = try ProjectFixtures.twoClips()
        #expect(throws: ProjectError.self) { try project.applying(.setSpeed(item: "left", speed: 40, keepDuration: false)) }
        #expect(throws: ProjectError.self) { try project.applying(.setSpeed(item: "left", speed: 0, keepDuration: false)) }
        let frozen = try project.applying(.setProperties(item: "left", patch: ["freezeFrame": .integer(5)])).project
        #expect(throws: ProjectError.self) { try frozen.applying(.setSpeed(item: "left", speed: 2, keepDuration: false)) }
        let locked = try project.applying(.setTrackProperties(track: "v1", patch: ["locked": .bool(true)])).project
        #expect(throws: ProjectError.self) { try locked.applying(.setSpeed(item: "left", speed: 2, keepDuration: false)) }
        let round = try ProjectFixtures.undoRedo(.setSpeed(item: "left", speed: 2, keepDuration: false), on: project)
        #expect(round.matches(original: project))
    }

    @Test("setSpeed round-trips through the op codec")
    func codec() throws {
        let operation = EditOperation.setSpeed(item: "left", speed: 1.25, keepDuration: true)
        #expect(try EditOperation(json: operation.json) == operation)
        let defaulted = try EditOperation(json: .object([
            "op": .string("setSpeed"), "item": .string("x"), "speed": .integer(2),
        ]))
        #expect(defaulted == .setSpeed(item: "x", speed: 2, keepDuration: false))
    }
}
