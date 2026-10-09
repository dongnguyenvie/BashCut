import Testing

@testable import BashCutProject

/// Text and picture facts in `review.layout` (P0-B6) and scale facts (P0-B7).
struct ReviewLayoutFactsTests {
    let layout = ReviewLayoutTests()

    @Test("Titles report hold, reading speed, speech, caption overlap and repeats; density per minute")
    func textFacts() throws {
        var project = layout.project([layout.text("cap", "chào các bạn")])
        project.tracks.insert(Track(id: "titles", kind: TrackKind.text, role: "titles"), at: 0)
        var title = layout.text("title", "Hôm nay mình đi chợ", at: 30)
        title["textPreset"] = .string("hook-title")
        var second = layout.text("title2", "Chợ Bến Thành", at: 120)
        second["textPreset"] = .string("hook-title")
        project.tracks[0].items = [title, second]
        let words = [ReviewSync.WordSpan(at: 40, end: 70, text: "hôm")]
        let json = ReviewLayout.json(project, context: layout.context(bottom: 300), words: words).object
        let rows = try #require(json["items"]?.array).map(\.object)
        let row = try #require(rows.first { $0["id"] == .string("title") })
        #expect(row["holdSeconds"] == .number(2) && row["words"] == .integer(5) && row["wordsPerSecond"] == .number(2.5))
        #expect(row["speech"]?.object["onsetOffsetFrames"] == .integer(-10))
        #expect(row["speech"]?.object["narrationShare"] == .number(0.5))
        // Every box is the same 600×100 rectangle in this stand-in renderer: the title covers the caption fully.
        #expect(row["captionOverlap"] == .object(["item": .string("cap"), "ratio": .number(1)]))
        #expect(row["templateRepeats"] == .integer(2))
        #expect(row["faceOverlap"] == .null)
        let caption = try #require(rows.first { $0["id"] == .string("cap") })
        #expect(caption["captionOverlap"] == nil)
        #expect(json["density"]?.object["titles"] == .integer(2))
        #expect(json["facesProvider"] == .bool(false))
        #expect(ReviewLayout.json(project, context: layout.context(bottom: 300)).object["items"]?.array.first?.object["speech"] == nil)
    }

    @Test("Scale: base scale of fit or fill, zoom now and at its largest key, pixels per source pixel, coverage")
    func scale() throws {
        var project = Project(name: "Scale", fps: FrameRate(30, 1))
        project["format"] = .object(["width": .integer(2160), "height": .integer(3840), "fps": FrameRate(30, 1).json])
        let media = Media(fields: [
            "id": .string("m"), "path": .string("m.mp4"), "kind": .string("video"), "fps": FrameRate(30, 1).json,
            "frames": .integer(300), "width": .integer(1080), "height": .integer(1920),
        ])
        var item = Item(id: "a", media: "m", at: 0, duration: 60)
        item["keyframes"] = .object(["zoom": .array([
            .object(["frame": .integer(0), "value": .number(1)]), .object(["frame": .integer(59), "value": .number(1.5)]),
        ])])
        let facts = try #require(ReviewScale.json(item, media: media, project: project)).object
        #expect(facts["baseScale"] == .number(2) && facts["pixelRatio"] == .number(2))
        #expect(facts["maxZoom"] == .number(1.5) && facts["pixelRatioAtMaxZoom"] == .number(3))
        #expect(facts["maxZoomNative"] == .number(0.5))
        #expect(facts["frameCoverage"] == .number(1))

        // A landscape screen recording fitted into the portrait frame covers a third of it.
        let screen = Media(fields: [
            "id": .string("s"), "path": .string("s.mp4"), "kind": .string("video"), "fps": FrameRate(30, 1).json,
            "frames": .integer(300), "width": .integer(1920), "height": .integer(1080),
        ])
        var fitted = Item(id: "b", media: "s", at: 0, duration: 60)
        fitted["fill"] = .bool(false)
        let shrunk = try #require(ReviewScale.json(fitted, media: screen, project: project)).object
        #expect(shrunk["fit"] == .string("fit") && shrunk["shownWidth"] == .number(2160))
        #expect(shrunk["frameCoverage"] == .number(0.316))
    }
}
