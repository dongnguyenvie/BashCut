import BashCutProjectFixtures
import Testing

@testable import BashCutProject

struct RippleDeleteRangeTests {
    /// A 30 fps project cut at frames 90–120 in the tests:
    /// - Main: c1 0–60, c2 60–150 (linked sound on A1, keyframe at 70), c3 150–240 (keyframe at 10);
    /// - Overlay: o1 60–95, o2 95–115 (inside), a transition o1→o2; camera picture p 50–200, its sound d on A2;
    /// - Captions (two layers): k1 70–110 "a b c d", k2 80–140 "w x y z"; SFX s1 80–100, s2 110–130;
    /// - Music bed 0–300 on A3 with a beat grid; sections at 0, 100 and 200; transitions c1→c2 and c2→c3.
    private func project() throws -> Project {
        func linked(_ id: String, at: Int, duration: Int, sourceIn: Int) -> [EditOperation] {
            var video = Item(id: id, media: "m", at: at, duration: duration, sourceIn: sourceIn)
            video.fields["linkedAudio"] = .string(id + "-a")
            var audio = Item(id: id + "-a", media: "m", at: at, duration: duration, sourceIn: sourceIn)
            audio.fields["linkedVideo"] = .string(id)
            if id == "c2" { video.fields["keyframes"] = .object(["opacity": .array([key(70)])]) }
            if id == "c3" { video.fields["keyframes"] = .object(["opacity": .array([key(10)])]) }
            return [.insert(track: "v1", item: video), .insert(track: "a1", item: audio)]
        }
        func key(_ frame: Int) -> JSONValue { .object(["frame": .integer(frame), "value": .number(0.5)]) }
        func caption(_ id: String, track: String, at: Int, duration: Int, words: [(String, Int)]) -> EditOperation {
            var item = Item(id: id, at: at, duration: duration)
            item["text"] = .string(words.map(\.0).joined(separator: " "))
            item["words"] = .array(words.map { .object(["text": .string($0.0), "at": .integer($0.1), "dur": .integer(10)]) })
            return .insert(track: track, item: item)
        }
        var ops: [EditOperation] = [
            .addMedia(ProjectFixtures.media("m", frames: 1200, kind: "video", hasAudio: true)),
            .addMedia(ProjectFixtures.media("song", path: "song.m4a", frames: 3000, fps: FrameRate(30, 1), kind: "audio",
                                            hasAudio: true)),
        ]
        ops += linked("c1", at: 0, duration: 60, sourceIn: 0)
        ops += linked("c2", at: 60, duration: 90, sourceIn: 200)
        ops += linked("c3", at: 150, duration: 90, sourceIn: 600)
        ops += [
            .insert(track: "v2", item: Item(id: "o1", media: "m", at: 60, duration: 35, sourceIn: 0)),
            .insert(track: "v2", item: Item(id: "o2", media: "m", at: 95, duration: 20, sourceIn: 100)),
            .addTrack(track: Track(id: "v3", kind: "video", role: "overlay"), atIndex: EditOperation.frontLayer),
            .insert(track: "v3", item: Item(id: "p", media: "m", at: 50, duration: 150, sourceIn: 0)),
            .insert(track: "a2", item: Item(id: "d", media: "m", at: 50, duration: 150, sourceIn: 0)),
            .addTrack(track: Track(id: "t2", kind: "text", role: "captions"), atIndex: EditOperation.frontLayer),
            caption("k1", track: "t1", at: 70, duration: 40, words: [("a", 0), ("b", 10), ("c", 20), ("d", 30)]),
            caption("k2", track: "t2", at: 80, duration: 60, words: [("w", 0), ("x", 15), ("y", 30), ("z", 45)]),
            .insert(track: "a4", item: Item(id: "s1", media: "m", at: 80, duration: 20, sourceIn: 0)),
            .insert(track: "a4", item: Item(id: "s2", media: "m", at: 110, duration: 20, sourceIn: 0)),
            .insert(track: "a3", item: Item(id: "bed", media: "song", at: 0, duration: 300, sourceIn: 0)),
            .setBeatGrid(media: "song", bpm: 120, frames: [0, 100, 200, 290], provenance: nil),
            .upsertSection(id: "intro", label: "Intro", atFrame: 0),
            .upsertSection(id: "mid", label: "Mid", atFrame: 100),
            .upsertSection(id: "end", label: "End", atFrame: 200),
            .upsertTransition(id: "t12", kind: "dissolve", from: "c1", to: "c2", duration: 10),
            .upsertTransition(id: "t23", kind: "dissolve", from: "c2", to: "c3", duration: 10),
            .upsertTransition(id: "to", kind: "dissolve", from: "o1", to: "o2", duration: 10),
        ]
        return try Project(name: "Ripple range", fps: FrameRate(30, 1))
            .applying(.group(label: "Setup", author: .user, ops: ops)).project
    }

    private func items(_ project: Project) -> [String: Item] {
        Dictionary(uniqueKeysWithValues: project.tracks.flatMap(\.items).map { ($0.id, $0) })
    }

    private func cut(_ project: Project, tracks: [String]? = nil, continuous: [String]? = nil) throws -> EditResult {
        try project.applying(.rippleDeleteRange(from: 90, to: 120, tracks: tracks, continuous: continuous))
    }

    @Test("Items inside the range go, items over one edge are trimmed and later items move left")
    func insideAndEdges() throws {
        let original = try project()
        let result = try cut(original)
        let after = items(result.project)
        #expect(after["o2"] == nil)
        #expect(after["o1"]?.at == 60 && after["o1"]?.duration == 30)
        #expect(after["s1"]?.at == 80 && after["s1"]?.duration == 10)
        // s2 starts 10 frames later in its source (1/3 s of a 60 fps source) and moves to the cut.
        #expect(after["s2"]?.at == 90 && after["s2"]?.duration == 10 && after["s2"]?.sourceIn == 20)
        #expect(after["c3"]?.at == 120 && after["c3-a"]?.at == 120)
        #expect(after["c3"]?.motion?.keys["opacity"]?.map(\.frame) == [10])
        #expect(result.project.duration == 270)
        #expect(throws: Never.self) { try result.project.validate() }
        var restored = try result.project.applying(result.inverse).project
        restored.revision = original.revision
        #expect(restored == original)
    }

    @Test("An item over the whole range is split and joined; linked halves stay linked and in sync")
    func spanning() throws {
        let after = items(try cut(try project()).project)
        let left = try #require(after["c2"]), right = try #require(after["c2-cut"])
        #expect(left.at == 60 && left.duration == 30 && left.sourceIn == 200)
        #expect(right.at == 90 && right.duration == 30 && right.sourceIn == 320)
        #expect(right.motion?.keys["opacity"]?.map(\.frame) == [10])
        let sound = try #require(after["c2-a-cut"])
        #expect(right.linkedItemID == "c2-a-cut" && sound.linkedItemID == "c2-cut")
        #expect(after["c2"]?.linkedItemID == "c2-a" && after["c2-a"]?.linkedItemID == "c2")
        #expect(sound.at == right.at && sound.duration == right.duration && sound.sourceIn == right.sourceIn)
        // The unlinked camera picture and its sound on another layer get the same cut, so they do not overlap.
        #expect(after["p"]?.duration == 40 && after["p-cut"]?.at == 90 && after["p-cut"]?.duration == 80)
        #expect(after["d"]?.duration == 40 && after["d-cut"]?.at == 90 && after["d-cut"]?.sourceIn == after["p-cut"]?.sourceIn)
    }

    @Test("Captions keep only the words outside the range, with their text")
    func captions() throws {
        let after = items(try cut(try project()).project)
        let k1 = try #require(after["k1"]), k2 = try #require(after["k2"])
        #expect(k1.at == 70 && k1.duration == 20 && k1.text == "a b")
        #expect(k2.at == 80 && k2.duration == 30 && k2.text == "w z")
        #expect(k2.fields["words"]?.array.compactMap { $0.object["at"]?.int } == [0, 15])
        #expect(after["k2-cut"] == nil)
    }

    @Test("Markers and sections move with the timeline; one inside the range goes to the cut")
    func markers() throws {
        let sections = try cut(try project()).project.sectionMarkers.map { "\($0.id)@\($0.at)" }
        #expect(sections.sorted() == ["end@170", "intro@0", "mid@90"])
    }

    @Test("Transitions on removed cuts go; one after a split part moves to its right part")
    func transitions() throws {
        let kept = try cut(try project()).project.transitions.map { "\($0.id):\($0.fromItemID)>\($0.toItemID)" }
        #expect(kept.sorted() == ["t12:c1>c2", "t23:c2-cut>c3"])
    }

    @Test("A music bed keeps its source running and loses its tail, unless continuous is empty")
    func musicBed() throws {
        let bed = try cut(try project()).project
        #expect(items(bed)["bed"]?.duration == 270 && items(bed)["bed"]?.sourceIn == 0 && items(bed)["bed-cut"] == nil)
        // The bed did not move, so its beats stay; the one past the new end goes.
        #expect(bed["beatGrid"]?.object["frames"]?.array.compactMap(\.int) == [0, 100, 200])
        let split = items(try cut(try project(), continuous: []).project)
        #expect(split["bed"]?.duration == 90 && split["bed-cut"]?.at == 90 && split["bed-cut"]?.sourceIn == 120)
    }

    @Test("tracks limits the cut to those layers and their linked partners")
    func limitedTracks() throws {
        let after = items(try cut(try project(), tracks: ["v1"]).project)
        #expect(after["c2-cut"] != nil && after["c2-a-cut"] != nil && after["c3-a"]?.at == 120)
        #expect(after["o2"]?.at == 95 && after["bed"]?.duration == 300)
        #expect(throws: ProjectError.self) { try cut(try project(), tracks: ["nope"]) }
        #expect(throws: ProjectError.self) {
            try project().applying(.rippleDeleteRange(from: 120, to: 90, tracks: nil, continuous: nil))
        }
    }

    @Test("The op round-trips through the wire codec")
    func codec() throws {
        let op = EditOperation.rippleDeleteRange(from: 90, to: 120, tracks: ["v1"], continuous: [])
        #expect(try EditOperation(json: op.json) == op)
        let plain = try EditOperation(json: .object(["op": .string("rippleDeleteRange"), "from": .integer(1), "to": .integer(5)]))
        #expect(plain == .rippleDeleteRange(from: 1, to: 5, tracks: nil, continuous: nil))
    }
}
