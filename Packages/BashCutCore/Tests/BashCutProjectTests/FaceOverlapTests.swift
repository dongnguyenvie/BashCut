import Testing

@testable import BashCutProject

/// `review.layout` faceOverlap and the `text-face` review check from stored face boxes (P0-B6, P2-H6).
struct FaceOverlapTests {
    let layout = ReviewLayoutTests()

    /// A 1080×1920 clip filling the 1080×1920 frame for 60 frames under a caption, and face boxes at 0–2 s:
    /// the face spans x 216–648 and y 1152–1344 px from the top.
    func scene(bottom: Double) -> (Project, ReviewContext) {
        var project = layout.project([layout.text("cap", "chào các bạn")])
        project.media = [Media(fields: [
            "id": .string("m"), "path": .string("m.mov"), "kind": .string("video"), "fps": FrameRate(30, 1).json,
            "frames": .integer(300), "width": .integer(1080), "height": .integer(1920),
        ])]
        let main = project.tracks.firstIndex { $0.id == "v1" }!
        project.tracks[main].items = [Item(id: "clip", media: "m", at: 0, duration: 60)]
        var context = layout.context(bottom: bottom)
        context.subjects = ["m": MediaSubjects(samples: (0...2).map { second in
            MediaSubjects.Sample(seconds: Double(second), faces: [
                MediaSubjects.Box(x: 0.2, y: 0.6, width: 0.4, height: 0.1, confidence: 0.8),
            ])
        }, step: 1)]
        return (project, context)
    }

    @Test("A caption over the lower part of a face reports the share of the face it covers")
    func overlap() throws {
        let (project, context) = scene(bottom: 576)
        let json = ReviewLayout.json(project, context: context).object
        #expect(json["facesProvider"] == .bool(true))
        let row = try #require(json["items"]?.array.first?.object)
        let face = try #require(row["faceOverlap"]?.object)
        // Text spans y 1244–1344 from the top: 100 of the face's 192 px.
        #expect(face["ratio"] == .number(0.521))
        #expect(face["item"] == .string("clip") && face["media"] == .string("m") && face["frame"] == .integer(0))
        #expect(face["samples"] == .integer(3) && face["confidence"] == .number(0.8))
    }

    @Test("Clear of the face: ratio 0; no stored boxes: null (unknown)")
    func clearAndUnknown() throws {
        let (project, context) = scene(bottom: 1500)
        let row = try #require(ReviewLayout.json(project, context: context).object["items"]?.array.first?.object)
        #expect(row["faceOverlap"]?.object["ratio"] == .number(0))
        let unknown = try #require(ReviewLayout.json(project, context: layout.context(bottom: 576)).object["items"]?.array.first?.object)
        #expect(unknown["faceOverlap"] == .null)
    }

    @Test("Panning the clip moves its faces: the overlap follows the transform")
    func followsPan() throws {
        var (project, context) = scene(bottom: 576)
        let main = project.tracks.firstIndex { $0.id == "v1" }!
        project.tracks[main].items[0]["transform"] = .object(["pan": .number(700)])
        let row = try #require(ReviewLayout.json(project, context: context).object["items"]?.array.first?.object)
        // The face now spans x 916–1348; the text box ends at 800.
        #expect(row["faceOverlap"]?.object["ratio"] == .number(0))
        context.subjects = [:]
        #expect(ReviewLayout.json(project, context: context).object["facesProvider"] == .bool(false))
    }

    @Test("text-face only with review.maxFaceOverlap set, above it")
    func reviewCheck() throws {
        var (project, context) = scene(bottom: 576)
        context.targets = ReviewTargets()
        #expect(!TimelineReview.run(project, context: context).contains { $0.kind == "text-face" })
        project["review"] = .object(["maxFaceOverlap": .number(0.25)])
        let issue = try #require(TimelineReview.run(project, context: context).first { $0.kind == "text-face" })
        #expect(issue.id == "text-face-cap" && issue.facts["ratio"] == .number(0.521))
        project["review"] = .object(["maxFaceOverlap": .number(0.6)])
        #expect(!TimelineReview.run(project, context: context).contains { $0.kind == "text-face" })
    }
}
