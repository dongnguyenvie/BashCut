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

    @Test("Several clips change speed in one group, each rippling its layer like one clip does")
    func several() throws {
        let project = try ProjectFixtures.twoClips()
        let (operations, skipped) = project.speedOperations(["left", "right", "nope"], speed: 2, keepDuration: false)
        #expect(operations.count == 2 && skipped == ["nope"])
        let fast = try project.applying(.group(label: "Speed 2×", author: .user, ops: operations)).project
        let one = try project.applying(.setSpeed(item: "left", speed: 2, keepDuration: false)).project
        #expect(try item(fast, "left").duration == item(one, "left").duration)
        #expect(try item(fast, "right").at == item(fast, "left").end && item(fast, "right").speed == 2)
        #expect(try item(fast, "right").duration == (item(project, "right").duration / 2))
        let pair = try ProjectFixtures.linkedPair()
        let linked = pair.speedOperations(["v", "a"], speed: 1.5, keepDuration: false)
        #expect(linked.operations == [.setSpeed(item: "v", speed: 1.5, keepDuration: false)] && linked.skipped.isEmpty)
    }

    @Test("A speed that does not divide the clip rounds down, so the out edge never plays past its old source")
    func outEdgeRoundsDown() throws {
        let project = try ProjectFixtures.twoClips()
        // 60 / 1.6 = 37.5 frames: 38 would play 2.027 s of a clip that played 2 s, into the next word.
        let fast = try project.applying(.setSpeed(item: "left", speed: 1.6, keepDuration: false)).project
        let left = try item(fast, "left")
        #expect(try left.duration == 37 && item(fast, "right").at == 37)
        #expect(left.sourceSeconds(afterFrames: left.duration, fps: fast.fps) <= 2)
    }

    /// `twoClips` with captions made from its media: "One both" heard at 0.5–1.5 s in `left` and "Two" at 2.5–3.5 s
    /// in `right`, plus a typed caption that is not from the media.
    private func captioned() throws -> Project {
        var project = try ProjectFixtures.twoClips()
        let srt = "1\n00:00:00,500 --> 00:00:01,500\nOne both\n\n2\n00:00:02,500 --> 00:00:03,500\nTwo\n"
        let words = [
            CaptionWords.Timed(text: "One", start: 0.5, end: 1), CaptionWords.Timed(text: "both", start: 1, end: 1.5),
            CaptionWords.Timed(text: "Two", start: 2.5, end: 3.5),
        ]
        project = try project.applying(project.importingSubRip(srt, media: "m", words: words)).project
        var typed = Item(id: "typed", at: 110, duration: 10)
        typed.fields["text"] = .string("Typed")
        return try project.applying(.insert(track: "t1", item: typed)).project
    }

    private func captions(_ project: Project) -> [Item] {
        project.tracks.filter { $0.role == TrackRole.captions }.flatMap(\.items).sorted { $0.at < $1.at }
    }

    @Test("Captions made from the media follow the sped clip and the clips it ripples, keeping word timings")
    func captionsFollow() throws {
        let project = try captioned()
        #expect(captions(project).map(\.at) == [15, 75, 110])
        let fast = try project.applying(.setSpeed(item: "left", speed: 1.5, keepDuration: false)).project
        let moved = captions(fast)
        // left is 40 frames now and right starts at 40: its caption moves with it; the typed one stays.
        #expect(moved.map(\.text) == ["One both", "Two", "Typed"])
        #expect(moved.map(\.at) == [10, 55, 110] && moved.map(\.end) == [30, 85, 120])
        let words = try #require(moved.first?.fields["words"]?.array).map(\.object)
        #expect(words.map { $0["at"]?.int } == [0, 10] && words.map { $0["dur"]?.int } == [10, 10])
        // Slowing down stretches them the other way.
        let slow = try project.applying(.setSpeed(item: "left", speed: 0.5, keepDuration: false)).project
        #expect(captions(slow).map(\.at) == [30, 110, 135] && captions(slow).map(\.end) == [90, 120, 165])
        let round = try ProjectFixtures.undoRedo(.setSpeed(item: "left", speed: 1.5, keepDuration: false), on: project)
        #expect(round.matches(original: project))
    }

    @Test("Slowing at the same length keeps only the words the clip still plays the middle of")
    func captionsLoseUnplayedWords() throws {
        let project = try captioned()
        // `left` plays 0–1 s at 0.5× now: "One" (middle 0.75 s) is heard at 30–60, "both" (1.25 s) no longer.
        let slow = try project.applying(.setSpeed(item: "left", speed: 0.5, keepDuration: true)).project
        let first = try #require(captions(slow).first)
        #expect(first.at == 30 && first.end == 60)
        #expect(first.fields["words"]?.array.compactMap { $0.object["text"]?.string } == ["One"])
        #expect(captions(slow).first { $0.text == "Two" }?.at == 75)
    }

    @Test("A retimed caption that would overlap a caption left on its layer goes to another caption layer")
    func captionsStack() throws {
        var project = try captioned()
        var typed = Item(id: "late", at: 125, duration: 10)
        typed.fields["text"] = .string("Late")
        project = try project.applying(.insert(track: "t1", item: typed)).project
        // At 0.75× `right` starts at 80, so "Two" lands on 95–125, over "typed".
        let slow = try project.applying(.setSpeed(item: "left", speed: 0.75, keepDuration: false)).project
        let layers = slow.tracks.filter { $0.role == TrackRole.captions }
        #expect(layers.count == 2)
        #expect(layers.last?.items.map(\.text) == ["Two"])
        #expect(try item(slow, "typed").at == 110 && item(slow, "late").at == 125)
    }

    @Test("A ramp retimes the clip's captions through the curve")
    func captionsFollowRamp() throws {
        let project = try captioned()
        let curve = try SpeedCurve([.init(t: 0, speed: 1), .init(t: 1, speed: 3)])
        let ramped = try project.applying(.setSpeedCurve(item: "left", curve: curve, keepDuration: false)).project
        let left = try item(ramped, "left"), first = try #require(captions(ramped).first)
        let start = left.sourceSeconds(afterFrames: first.at - left.at, fps: ramped.fps)
        #expect(abs(start - 0.5) < 0.05)
        #expect(try captions(ramped).first { $0.text == "Two" }?.at == item(ramped, "right").at + 15)
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
