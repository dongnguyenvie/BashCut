import Foundation
import Testing

@testable import BashCutProject

/// The shots as a sequence (P0-B1): cut facts, runs and shares from descriptions, rhythm overall and per section,
/// keyframe camera moves, and the same facts for a source file.
struct ReviewSequenceTests {
    /// Main at 30 fps over a 20 s, 30 fps media described as MS/static 0–8 s, MS/static 8–12 s, CU/push 12–20 s.
    /// Shots: a (0–2 s of source), b (2–4 s, adjacent), c (9–10 s), d (14–16 s, keyframed push-in); a section
    /// marker "B" at frame 120.
    func project() -> Project {
        var project = Project(name: "Sequence", fps: FrameRate(30, 1))
        let shot = { (start: Double, end: Double, size: String, move: String) -> JSONValue in
            .object(["start": .number(start), "end": .number(end), "size": .string(size), "move": .string(move)])
        }
        project.media = [
            Media(fields: [
                "id": .string("m"), "path": .string("m.mp4"), "kind": .string("video"), "fps": FrameRate(30, 1).json,
                "frames": .integer(600),
                "description": .object(["shots": .array([
                    shot(0, 8, "MS", "static"), shot(8, 12, "MS", "static"), shot(12, 20, "CU", "push"),
                ])]),
            ])
        ]
        var d = Item(id: "d", media: "m", at: 150, duration: 60, sourceIn: 420)
        d["keyframes"] = .object(["zoom": .array([
            .object(["frame": .integer(0), "value": .number(1), "ease": .string("linear")]),
            .object(["frame": .integer(60), "value": .number(1.2)]),
        ])])
        let index = project.tracks.firstIndex { $0.id == "v1" }!
        project.tracks[index].items = [
            Item(id: "a", media: "m", at: 0, duration: 60), Item(id: "b", media: "m", at: 60, duration: 60, sourceIn: 60),
            Item(id: "c", media: "m", at: 120, duration: 30, sourceIn: 270), d,
        ]
        project.markers = [TimelineMarker(at: 120, kind: "section", label: "B")]
        return project
    }

    @Test("Each cut says whether it stays in the setup, how far the source jumps and how size and move change")
    func cuts() throws {
        let shots = try #require(ReviewShots.json(project()).object["shots"]?.array).map(\.object)
        #expect(shots[0]["cut"] == nil)
        let ab = try #require(shots[1]["cut"]).object
        #expect(ab["sameMedia"] == .bool(true) && ab["sameSetup"] == .bool(true))
        #expect(ab["sourceGapSeconds"] == .number(0))
        let bc = try #require(shots[2]["cut"]).object
        #expect(bc["sameSetup"] == .bool(false) && bc["sourceGapSeconds"] == .number(5))
        #expect(bc["size"] == .object(["from": .string("MS"), "to": .string("MS")]))
        let cd = try #require(shots[3]["cut"]).object
        #expect(cd["size"] == .object(["from": .string("MS"), "to": .string("CU")]))
        #expect(cd["move"] == .object(["from": .string("static"), "to": .string("push")]))
        let move = try #require(shots[3]["cameraMove"]?.array.first).object
        #expect(move["property"] == .string("zoom") && move["perSecond"] == .number(10) && move["unit"] == .string("%"))
        #expect(move["ease"] == .string("linear"))
        #expect(shots[0]["cameraMove"] == nil)
    }

    @Test("The summary lists runs of the same size and move, shares, and rhythm overall and per section")
    func summary() throws {
        let json = ReviewShots.json(project(), summary: true, lowVariance: .init(runLength: 2, maxCV: 0.05)).object
        let runs = try #require(json["runs"]?.array).map(\.object)
        #expect(runs.count == 1)
        #expect(runs[0]["fromIndex"] == .integer(0) && runs[0]["count"] == .integer(3) && runs[0]["size"] == .string("MS"))
        let shares = try #require(json["shares"]).object
        #expect(shares["size"]?.object["MS"]?.object["share"] == .number(0.75))
        #expect(shares["described"] == .integer(4))
        let rhythm = try #require(json["rhythm"]).object
        let overall = try #require(rhythm["overall"]).object
        #expect(overall["count"] == .integer(4))
        // Lengths 2, 2, 1, 2 s.
        #expect(overall["mode"]?.object["share"] == .number(0.75))
        #expect(overall["lowVarianceRuns"]?.array.first?.object["count"] == .integer(2))
        #expect(abs((overall["cv"]?.double ?? 0) - 0.2474) < 0.001)
        let sections = try #require(rhythm["sections"]?.array).map(\.object)
        #expect(sections.map { $0["label"] } == [.string("B")])
        #expect(sections[0]["count"] == .integer(2))
        #expect(ReviewShots.json(project(), summary: true).object["rhythm"]?.object["overall"]?.object["lowVarianceRuns"] == nil)
    }

    @Test("A source file's measured shots give the same sequence facts")
    func media() throws {
        let analysis = MediaAnalysisTests().record()
        let media = Media(fields: [
            "id": .string("m"), "path": .string("m.mp4"), "fps": FrameRate(30, 1).json, "frames": .integer(300),
            "description": .object(["shots": .array([
                .object(["start": .number(0), "end": .number(3), "size": .string("WS"), "move": .string("pan")]),
                .object(["start": .number(3), "end": .number(10), "size": .string("WS"), "move": .string("pan")]),
            ])]),
        ])
        let json = ReviewShots.json(media: media, record: analysis, minScore: 0.1, lowVariance: nil).object
        let shots = try #require(json["shots"]?.array).map(\.object)
        #expect(shots.count == 3)
        #expect(shots[1]["cut"]?.object["sameSetup"] == .bool(true))
        #expect(shots[2]["described"]?.object["size"] == .string("WS"))
        #expect(json["runs"]?.array.first?.object["count"] == .integer(3))
        #expect(json["rhythm"]?.object["cutsPerMinute"] == .number(12))
    }
}
