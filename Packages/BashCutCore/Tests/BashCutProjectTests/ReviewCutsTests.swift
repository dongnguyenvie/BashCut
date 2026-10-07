import Foundation
import Testing

@testable import BashCutProject

/// Cut inventory and timing against beats and words (P0-B2).
struct ReviewCutsTests {
    /// Main at 30 fps: a (0–60), b (60–120, same media, punched in to 1.3), dissolve into c (120–180), d (190–240)
    /// after a 10-frame gap. Beats every 30 frames from 0; a text item at 62, an sfx at 119.
    func project() -> Project {
        var project = Project(name: "Cuts", fps: FrameRate(30, 1))
        project.media = [
            Media(fields: ["id": .string("m"), "path": .string("m.mp4"), "fps": FrameRate(30, 1).json, "frames": .integer(900)])
        ]
        var b = Item(id: "b", media: "m", at: 60, duration: 60, sourceIn: 60)
        b["transform"] = .object(["zoom": .number(1.3)])
        let main = project.tracks.firstIndex { $0.role == TrackRole.main }!
        project.tracks[main].items = [
            Item(id: "a", media: "m", at: 0, duration: 60), b, Item(id: "c", media: "m", at: 120, duration: 60, sourceIn: 300),
            Item(id: "d", media: "m", at: 190, duration: 50, sourceIn: 500),
        ]
        project.transitions = [TimelineTransition(kind: "dissolve", from: "b", to: "c", duration: 12)]
        project.tracks.insert(Track(id: "titles", kind: TrackKind.text, role: "titles"), at: 0)
        project.tracks[0].items = [Item(fields: ["id": .string("t"), "at": .integer(62), "dur": .integer(30), "text": .string("Hi")])]
        project.tracks.append(Track(id: "s1", kind: TrackKind.audio, role: TrackRole.sfx))
        project.tracks[project.tracks.count - 1].items = [Item(id: "s", media: "m", at: 119, duration: 10)]
        project["beatGrid"] = .object([
            "media": .string("m"), "bpm": .number(60), "frames": .array(stride(from: 0, through: 240, by: 30).map(JSONValue.integer)),
        ])
        return project
    }

    @Test("Cuts carry kind, transition, gap and framing on both sides; counts and runs per kind")
    func inventory() throws {
        let json = ReviewCuts.json(project()).object
        let cuts = try #require(json["cuts"]?.array).map(\.object)
        #expect(cuts.map { $0["kind"] } == [.string("hard"), .string("dissolve"), .string("hard")])
        #expect(cuts[0]["framingAfter"]?.object["zoom"] == .number(1.3))
        #expect(cuts[0]["sameFraming"] == .bool(false))
        #expect(cuts[1]["transitionFrames"] == .integer(12) && cuts[1]["easing"] == .string("linear"))
        #expect(cuts[2]["gapFrames"] == .integer(10))
        #expect(cuts[2]["sameFraming"] == .bool(true))
        #expect(json["counts"] == .object(["hard": .integer(2), "dissolve": .integer(1)]))
        #expect(json["runs"] == .array([]))
        #expect(json["sameFraming"] == .integer(1))
    }

    @Test("Events are timed against the nearest beat and word edge, with the distribution")
    func sync() throws {
        let words = [
            ReviewSync.WordSpan(at: 50, end: 58, text: "xin"), ReviewSync.WordSpan(at: 118, end: 130, text: "chào"),
        ]
        let json = ReviewSync.json(project(), words: words, kinds: [.cuts, .text, .sfx]).object
        let events = try #require(json["events"]?.array).map(\.object)
        #expect(events.map { $0["kind"] } == [.string("cut"), .string("text"), .string("sfx"), .string("cut"), .string("cut")])
        let first = try #require(events[0]["beat"]).object
        #expect(first["offsetFrames"] == .integer(0))
        let word = try #require(events[0]["word"]).object
        #expect(word["edge"] == .string("end") && word["offsetFrames"] == .integer(2) && word["offsetMs"] == .number(67))
        #expect(events[2]["beat"]?.object["offsetFrames"] == .integer(-1))
        #expect(events[3]["word"]?.object["inside"] == .bool(true))
        let beat = try #require(json["beat"]).object
        #expect(beat["count"] == .integer(5))
        #expect(beat["byOffset"]?.object["10"] == nil && beat["byOffset"]?.object["-1"] == .integer(1))
        #expect(ReviewSync.json(project(), words: []).object["word"] == .object(["count": .integer(0)]))
    }
}
