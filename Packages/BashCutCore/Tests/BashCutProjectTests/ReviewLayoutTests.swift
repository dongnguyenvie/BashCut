import Testing

@testable import BashCutProject

/// Text layout for agents and the text checks (#465): the renderer's boxes when given, the estimate otherwise.
struct ReviewLayoutTests {
    /// A 1080×1920 project with `items` on the text track t1.
    func project(_ items: [Item]) -> Project {
        var project = Project(name: "Layout", fps: FrameRate(30, 1))
        let index = project.tracks.firstIndex { $0.id == "t1" }!
        project.tracks[index].items = items
        return project
    }

    func text(_ id: String, _ value: String, at: Int = 0) -> Item {
        var item = Item(id: id, at: at, duration: 60)
        item["text"] = .string(value)
        return item
    }

    /// A renderer stand-in: every box 600×100 px, 200 px from the left and `bottom` px from the bottom.
    func context(bottom: Double, platform: OutputPlatform? = .tiktok) -> ReviewContext {
        ReviewContext(
            textLayout: { _, _, _ in TextLayout(points: 64.8, lines: 1, minX: 200, maxX: 800, minY: bottom, maxY: bottom + 100) },
            targets: ReviewTargets(platform: platform))
    }

    @Test("Items carry the renderer's bounds, edges and font share next to the platform zones")
    func renderedBounds() throws {
        let project = project([text("a", "Xin chào"), text("b", "Sau", at: 90)])
        let json = ReviewLayout.json(project, context: context(bottom: 576)).object
        #expect(json["platform"]?.object["id"] == .string("tiktok"))
        let items = try #require(json["items"]?.array).map(\.object)
        #expect(items.count == 2)
        let first = items[0]
        #expect(first["measured"] == .bool(true))
        #expect(first["fontShare"] == .number(0.06))
        #expect(first["longestLineChars"] == .integer(8))
        #expect(first["bounds"] == .object([
            "x": .number(200), "y": .number(1244), "width": .number(600), "height": .number(100),
        ]))
        let edges = try #require(first["edges"]?.object)
        #expect(edges["bottom"] == .number(0.3))
        #expect(edges["left"] == .number(0.185))

        let atFrame = ReviewLayout.json(project, context: context(bottom: 576), frame: 100).object
        #expect(atFrame["items"]?.array.map(\.object["id"]) == [.string("b")])
    }

    @Test("Without a renderer the box is the estimate, marked as not measured")
    func estimate() throws {
        let project = project([text("a", "Xin chào")])
        let item = try #require(ReviewLayout.json(project, context: ReviewContext()).object["items"]?.array.first?.object)
        #expect(item["measured"] == .bool(false))
    }

    @Test("Text checks use the rendered box: a box low in the frame is under the caption bar, a high one is not")
    func checksUseRenderedBounds() {
        let project = project([text("a", "Xin chào")])
        let low = TimelineReview.run(project, context: context(bottom: 100))
        #expect(low.contains { $0.id == "safe-bottom-a" })
        let high = TimelineReview.run(project, context: context(bottom: 900))
        #expect(!high.contains { $0.id == "safe-bottom-a" })
    }
}
