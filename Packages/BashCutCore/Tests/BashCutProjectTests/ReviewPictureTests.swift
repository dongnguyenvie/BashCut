import Testing

@testable import BashCutProject

/// Picture checks (#432) on hand-made measurements: what counts, what passes and what a stale measurement does.
struct ReviewPictureTests {
    /// A 1080×1920, 30 fps project with the given shots on Main as (id, media, frames).
    func project(_ shots: [(String, String, Int)], width: Int = 1080, height: Int = 1920) throws -> Project {
        var project = Project(name: "Picture", fps: FrameRate(30, 1))
        if width != 1080 || height != 1920 {
            project = try project.applying(.setFormat(width: width, height: height)).project
        }
        var at = 0
        let index = project.tracks.firstIndex { $0.id == "v1" }!
        project.tracks[index].items = shots.map { id, media, frames in
            defer { at += frames }
            return Item(id: id, media: media, at: at, duration: frames)
        }
        return project
    }

    /// Samples every 15 frames over `duration`; `level(frame)` gives (luma, spread, change).
    func picture(
        _ project: Project, cuts: [String: Double] = [:], level: (Int) -> (Double, Double, Double)
    ) -> ReviewPicture {
        let samples = stride(from: 0, to: project.duration, by: 15).map { frame in
            let (luma, spread, change) = level(frame)
            return ReviewPicture.Sample(frame: frame, luma: luma, spread: spread, change: change)
        }
        return ReviewPicture(revision: project.revision, interval: 15, samples: samples, cuts: cuts)
    }

    @Test("Not measured: a note with a review.measure fix when asked for; a stale measurement does not count")
    func unmeasured() throws {
        let project = try project([("a", "m", 90)])
        let targets = ReviewTargets(measuresPicture: true)
        let note = TimelineReview.run(project, context: ReviewContext(targets: targets))
            .first { $0.id == "picture-unmeasured" }
        #expect(note?.severity == .info)
        #expect(note?.fix?.command == "review.measure")
        #expect(!TimelineReview.run(project).contains { $0.id == "picture-unmeasured" })
        let black = picture(project) { _ in (0, 0, 0) }
        let stale = ReviewPicture(revision: project.revision + 1, interval: 15, samples: black.samples, cuts: [:])
        let issues = TimelineReview.run(project, context: ReviewContext(picture: stale, targets: targets))
        #expect(!issues.contains { $0.id.hasPrefix("black-") })
        #expect(issues.contains { $0.id == "picture-unmeasured" })
    }

    @Test("Black picture: inside the edit an error with its range; at the end (a fade) info")
    func black() throws {
        let project = try project([("a", "m", 300)])
        let middle = picture(project) { frame in frame >= 90 && frame < 120 ? (0.01, 0.0, 0.5) : (0.5, 0.2, 0.05) }
        let issues = TimelineReview.run(project, context: ReviewContext(picture: middle))
        let black = try #require(issues.first { $0.id == "black-a+90" })
        #expect(black.severity == .error)
        #expect(black.endFrame == 120)
        #expect(black.json.object["endFrame"] == .integer(120))
        #expect(issues.first?.id == "black-a+90")
        let tail = picture(project) { frame in frame >= 270 ? (0.01, 0.0, 0.5) : (0.5, 0.2, 0.05) }
        #expect(TimelineReview.run(project, context: ReviewContext(picture: tail)).filter { $0.id.hasPrefix("black-") }
            .allSatisfy { $0.severity == .info })
        // Dark but detailed picture (a night shot) is not black.
        let night = picture(project) { _ in (0.03, 0.1, 0.05) }
        #expect(!TimelineReview.run(project, context: ReviewContext(picture: night)).contains { $0.id.hasPrefix("black-") })
    }

    @Test("Frozen picture: longer than the project allows, except a freeze frame placed on purpose")
    func frozen() throws {
        var project = try project([("a", "m", 300)])
        project["review"] = .object(["maxStillSeconds": .number(4)])
        let measured = picture(project) { frame in (0.5, 0.2, frame > 30 && frame <= 210 ? 0.001 : 0.05) }
        let issue = try #require(
            TimelineReview.run(project, context: ReviewContext(picture: measured)).first { $0.id.hasPrefix("still-") })
        #expect(issue.frame == 30)
        #expect(issue.endFrame == 225)
        #expect(issue.severity == .warning)
        // A project override lengthens the allowed still picture.
        project["review"] = .object(["maxStillSeconds": .number(10)])
        let relaxed = picture(project) { frame in (0.5, 0.2, frame > 30 && frame <= 210 ? 0.001 : 0.05) }
        #expect(!TimelineReview.run(project, context: ReviewContext(picture: relaxed)).contains { $0.id.hasPrefix("still-") })
        project["review"] = .object(["maxStillSeconds": .number(4)])
        let index = project.tracks.firstIndex { $0.id == "v1" }!
        project.tracks[index].items[0]["freezeFrame"] = .integer(10)
        let frozen = picture(project) { _ in (0.5, 0.2, 0.001) }
        #expect(!TimelineReview.run(project, context: ReviewContext(picture: frozen)).contains { $0.id.hasPrefix("still-") })
    }

    @Test("Jump cuts: only with the project's jumpCutChange; the fix is a hint, not a fixed punch-in (#468)")
    func jumpCuts() throws {
        var project = try project([("a", "take1", 60), ("b", "take2", 60), ("c", "take2", 60), ("d", "take3", 60)])
        let measured = picture(project, cuts: ["b": 0.02, "c": 0.01, "d": 0.3]) { _ in (0.5, 0.2, 0.05) }
        #expect(!TimelineReview.run(project, context: ReviewContext(picture: measured)).contains { $0.id.hasPrefix("jump-") })
        project["review"] = .object(["jumpCutChange": .number(0.06)])
        let issues = TimelineReview.run(project, context: ReviewContext(picture: measured))
        let jump = try #require(issues.first { $0.id == "jump-b" })
        #expect(jump.fix?.command == nil && jump.fix?.hint != nil)
        #expect(issues.contains { $0.id == "framing-c" })
        #expect(!issues.contains { $0.id == "jump-c" || $0.id == "jump-d" })
    }

    @Test("Shot length: without limits the shortest and longest are notes; with them, long still shots warn")
    func shots() throws {
        var project = try project([("flash", "m", 6), ("long", "m", 300), ("ok", "m", 90)])
        let bare = TimelineReview.run(project)
        #expect(bare.filter { $0.id.hasPrefix("shot-") }.map(\.id).sorted() == ["shot-long-long", "shot-short-flash"])
        #expect(bare.filter { $0.id.hasPrefix("shot-") }.allSatisfy { $0.severity == .info })
        project["review"] = .object([
            "minShotSeconds": .number(0.4), "maxShotSeconds": .number(8), "stillMotion": .number(0.02),
        ])
        let unmeasured = TimelineReview.run(project)
        #expect(unmeasured.first { $0.id == "shot-short-flash" }?.severity == .info)
        let long = try #require(unmeasured.first { $0.id == "shot-long-long" })
        #expect(long.severity == .info)
        #expect(long.frame == 6 && long.endFrame == 306)
        let still = picture(project) { _ in (0.5, 0.2, 0.01) }
        #expect(TimelineReview.run(project, context: ReviewContext(picture: still))
            .first { $0.id == "shot-long-long" }?.severity == .warning)
        let moving = picture(project) { _ in (0.5, 0.2, 0.08) }
        #expect(!TimelineReview.run(project, context: ReviewContext(picture: moving)).contains { $0.id == "shot-long-long" })
        project["review"] = .object(["maxShotSeconds": .number(20), "minShotSeconds": .number(0.1)])
        #expect(!TimelineReview.run(project).contains { $0.id.hasPrefix("shot-") })
    }

    @Test("Plugin check issues join the review of their revision, sorted with the built-in ones (#451)")
    func pluginIssues() throws {
        let project = try project([("a", "m", 90)])
        let reported = [
            ReviewIssue(id: "x.hook:weak", title: "Weak hook", detail: "", frame: 0, severity: .error, source: "x"),
            ReviewIssue(id: "x.hook:note", title: "Note", detail: "", frame: 0, severity: .info, source: "x"),
        ]
        let current = ReviewPluginIssues(revision: project.revision, issues: reported)
        let issues = TimelineReview.run(project, context: ReviewContext(pluginIssues: current))
        #expect(issues.first?.id == "x.hook:weak")
        #expect(issues.contains { $0.id == "x.hook:note" })
        #expect(issues.first?.json.object["source"] == .string("x"))
        let stale = ReviewPluginIssues(revision: project.revision + 1, issues: reported)
        #expect(!TimelineReview.run(project, context: ReviewContext(pluginIssues: stale)).contains { $0.source != nil })
    }

    @Test("Raw data (#463): samples and cuts with seconds, units and floors; a range and a stale measurement")
    func rawData() throws {
        let project = try project([("a", "m", 60), ("b", "n", 60)])
        let measured = picture(project, cuts: ["b": 0.0123456]) { frame in (0.5, 0.2, frame == 30 ? 0.001 : 0.05) }
        let json = measured.json(for: project).object
        #expect(json["current"] == .bool(true))
        #expect(json["interval"] == .integer(15))
        #expect(json["floors"]?.object["stillChange"] == .number(ReviewPicture.stillChange))
        let samples = try #require(json["samples"]?.array)
        #expect(samples.count == 8)
        let still = try #require(samples.first { $0.object["frame"] == .integer(30) }?.object)
        #expect(still["seconds"] == .number(1))
        #expect(still["change"] == .number(0.001))
        #expect(still["peak"] == .number(0.001))
        let cut = try #require(json["cuts"]?.array.first?.object)
        #expect(cut["item"] == .string("b"))
        #expect(cut["fromItem"] == .string("a"))
        #expect(cut["frame"] == .integer(60))
        #expect(cut["before"] == .integer(59))
        #expect(cut["difference"] == .number(0.01235))

        let range = measured.json(for: project, from: 0, to: 60, cuts: true).object
        #expect(range["samples"]?.array.count == 4)
        #expect(range["cuts"]?.array.isEmpty == true)
        let cutsOnly = measured.json(for: project, samples: false).object
        #expect(cutsOnly["samples"] == nil)

        let stale = ReviewPicture(revision: project.revision + 1, interval: 15, samples: [], cuts: ["gone": 0.5])
        let staleJSON = stale.json(for: project).object
        #expect(staleJSON["current"] == .bool(false))
        #expect(staleJSON["cuts"]?.array.first?.object["frame"] == nil)
    }
}
