import Testing

@testable import BashCutProject

/// The shot list for agents (#464): timing, source, framing, cut and motion facts, and the summary.
struct ReviewShotsTests {
    /// Main at 30 fps: a (60 frames, zoom 1.2, keyframed scale), b (30 frames, from source frame 50 of a 25 fps
    /// clip), a dissolve into c (90 frames, at half speed).
    func project() -> Project {
        var project = Project(name: "Shots", fps: FrameRate(30, 1))
        project.media = [
            Media(fields: ["id": .string("m"), "kind": .string("video"), "fps": .array([.integer(25), .integer(1)])])
        ]
        var a = Item(id: "a", media: "m", at: 0, duration: 60)
        a["transform"] = .object(["zoom": .number(1.2)])
        a["keyframes"] = .object(["scale": .array([])])
        var c = Item(id: "c", media: "m", at: 90, duration: 90)
        c["speed"] = .number(0.5)
        let index = project.tracks.firstIndex { $0.id == "v1" }!
        project.tracks[index].items = [a, Item(id: "b", media: "m", at: 60, duration: 30, sourceIn: 50), c]
        project.transitions = [TimelineTransition(kind: "dissolve", from: "b", to: "c", duration: 10)]
        return project
    }

    @Test("Shots carry timing, source, framing and the cut into them; no motion without a measurement")
    func timeline() throws {
        let project = project()
        let json = ReviewShots.json(project).object
        #expect(json["pictureMeasured"] == .bool(false))
        #expect(json["summary"] == nil)
        let shots = try #require(json["shots"]?.array).map(\.object)
        #expect(shots.map { $0["id"] } == [.string("a"), .string("b"), .string("c")])
        #expect(shots[0]["zoom"] == .number(1.2))
        #expect(shots[0]["keyframed"] == .array([.string("scale")]))
        #expect(shots[0]["gapBefore"] == nil)
        #expect(shots[1]["seconds"] == .number(1))
        #expect(shots[1]["sourceInSeconds"] == .number(2))
        #expect(shots[1]["gapBefore"] == .integer(0))
        #expect(shots[1]["zoom"] == .number(1))
        #expect(shots[2]["speed"] == .number(0.5))
        #expect(shots[2]["transitionIn"]?.object["kind"] == .string("dissolve"))
        #expect(shots[2]["motion"] == nil)
    }

    @Test("Motion and cut difference come from a measurement of this revision only; summary statistics")
    func measured() throws {
        let project = project()
        let samples = stride(from: 0, to: project.duration, by: 15).map { frame in
            ReviewPicture.Sample(frame: frame, luma: 0.5, spread: 0.2, change: frame < 60 ? 0.01 : 0.03, peak: 0.2)
        }
        let picture = ReviewPicture(revision: project.revision, interval: 15, samples: samples, cuts: ["b": 0.4])
        let shots = try #require(ReviewShots.json(project, picture: picture, summary: true).object["shots"]?.array)
            .map(\.object)
        let motion = try #require(shots[0]["motion"]?.object)
        #expect(motion["mean"] == .number(0.01))
        #expect(motion["peak"] == .number(0.2))
        #expect(motion["samples"] == .integer(3))
        #expect(shots[1]["cutDifference"] == .number(0.4))
        #expect(shots[2]["cutDifference"] == nil)

        let summary = try #require(ReviewShots.json(project, summary: true).object["summary"]?.object)
        #expect(summary["count"] == .integer(3))
        #expect(summary["medianSeconds"] == .number(2))
        #expect(summary["minSeconds"] == .number(1))
        #expect(summary["maxSeconds"] == .number(3))
        #expect(summary["cutsPerMinute"] == .number(20))

        let stale = ReviewPicture(revision: project.revision + 1, interval: 15, samples: samples, cuts: [:])
        let staleJSON = ReviewShots.json(project, picture: stale).object
        #expect(staleJSON["pictureMeasured"] == .bool(false))
        #expect(staleJSON["pictureRevision"] == .integer(project.revision + 1))
    }
}
