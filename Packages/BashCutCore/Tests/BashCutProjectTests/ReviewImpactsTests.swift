import Foundation
import Testing

@testable import BashCutProject

/// Whole-picture hits and sound-effect runs in review.sync (#518, #519).
struct ReviewImpactsTests {
    /// Main at 30 fps: a (0–120) with a zoom punch at 30 (8 frames) and a slow zoom from 60 to 120; b (120–240)
    /// after a 4-frame blink; a 6-frame flash picture on an overlay at 200. Beats every 15 frames.
    func project() -> Project {
        var project = Project(name: "Impacts", fps: FrameRate(30, 1))
        project.media = [
            Media(fields: ["id": .string("m"), "path": .string("m.mp4"), "fps": FrameRate(30, 1).json, "frames": .integer(900)]),
            Media(fields: ["id": .string("pop"), "path": .string("pop.wav"), "fps": FrameRate(30, 1).json, "frames": .integer(30)]),
            Media(fields: ["id": .string("hit"), "path": .string("hit.wav"), "fps": FrameRate(30, 1).json, "frames": .integer(30)]),
        ]
        var a = Item(id: "a", media: "m", at: 0, duration: 120)
        a["keyframes"] = .object(["zoom": .array([
            .object(["frame": .integer(30), "value": .number(1.3)]), .object(["frame": .integer(38), "value": .number(1)]),
            .object(["frame": .integer(60), "value": .number(1)]), .object(["frame": .integer(120), "value": .number(1.1)]),
        ])])
        let main = project.tracks.firstIndex { $0.role == TrackRole.main }!
        project.tracks[main].items = [a, Item(id: "b", media: "m", at: 120, duration: 120, sourceIn: 200)]
        project.transitions = [TimelineTransition(kind: "blink", from: "a", to: "b", duration: 4)]
        project.tracks.insert(Track(id: "v2", kind: TrackKind.video, role: "overlay"), at: 0)
        project.tracks[0].items = [Item(id: "flash", media: "m", at: 200, duration: 6)]
        var sfx = Track(id: "s1", kind: TrackKind.audio, role: TrackRole.sfx)
        sfx.items = (0..<4).map { Item(id: "p\($0)", media: "pop", at: 30 + $0 * 10, duration: 8) }
            + [Item(id: "h", media: "hit", at: 100, duration: 8)]
        project.tracks.append(sfx)
        project["beatGrid"] = .object([
            "media": .string("m"), "bpm": .number(120), "frames": .array(stride(from: 0, through: 240, by: 15).map(JSONValue.integer)),
        ])
        return project
    }

    @Test("Fast keys, short transitions and short overlays count as impacts; slow moves do not")
    func impacts() throws {
        let json = ReviewImpacts.impactsJSON(project(), window: 12, beatStrengths: [30: 1, 120: 0.2]).object
        let events = try #require(json["events"]?.array).map(\.object)
        #expect(events.map { $0["source"] } == [.string("keyframes"), .string("transition"), .string("overlay")])
        #expect(events[0]["frame"] == .integer(30))
        #expect(events[0]["changes"]?.object["zoom"] == .array([.number(1.3), .number(1)]))
        #expect(events[0]["beat"]?.object["strength"] == .number(1))
        #expect(events[1]["kind"] == .string("blink"))
        #expect(events[1]["beatsSincePrevious"] == .integer(5))
        let summary = try #require(json["summary"]).object
        #expect(summary["count"] == .integer(3))
        #expect(summary["minSpacingBeats"] == .integer(5))
        #expect(summary["onStrongestQuarterOfBeats"] == .integer(1))
    }

    @Test("A wider window also counts the slow zoom")
    func window() throws {
        let events = try #require(ReviewImpacts.impactsJSON(project(), window: 60).object["events"]?.array)
        #expect(events.count == 4)
    }

    @Test("Three or more of one sound close together form a run with its gains and spacing")
    func sfxRuns() throws {
        let runs = try #require(ReviewImpacts.sfxRunsJSON(project()).array).map(\.object)
        #expect(runs.count == 1)
        #expect(runs[0]["media"] == .string("pop") && runs[0]["count"] == .integer(4))
        #expect(runs[0]["intervalsFrames"] == .array([.integer(10), .integer(10), .integer(10)]))
        #expect(runs[0]["constantGain"] == .bool(true) && runs[0]["constantSpacing"] == .bool(true))
        var varied = project()
        let index = varied.tracks.firstIndex { $0.id == "s1" }!
        varied.tracks[index].items[1]["volumeDb"] = .number(-4)
        let gains = try #require(ReviewImpacts.sfxRunsJSON(varied).array.first?.object)
        #expect(gains["constantGain"] == .bool(false))
    }
}
