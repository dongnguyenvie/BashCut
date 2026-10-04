import BashCutProject
import CoreGraphics
import Testing
@testable import BashCutEngine

struct TextCacheTests {
    private let size = CGSize(width: 320, height: 180)
    private func caption() -> Item {
        var item = Item(id: "caption", at: 0, duration: 30)
        item["text"] = .string("Xin chào thế giới")
        item["wordStyle"] = .string("highlight")
        return item
    }

    @Test("Timing, IDs and compositor transforms reuse the same caption raster")
    func nonDrawingEdits() throws {
        let original = caption()
        let image = try #require(TextRenderer.image(original, size: size, spoken: 1))
        var moved = original
        for (key, value): (String, JSONValue) in [
            ("id", .string("duplicate")), ("at", .integer(120)), ("dur", .integer(90)),
            ("opacity", .number(0.5)), ("transform", .object(["zoom": .number(2)])),
            ("words", .array([.object(["at": .integer(40), "dur": .integer(10)])])),
            ("keyframes", ItemMotion(keys: ["zoom": [.init(frame: 0, value: 1), .init(frame: 20, value: 2)]]).json)
        ] {
            moved[key] = value
            #expect(TextRenderer.cacheKey(moved) == TextRenderer.cacheKey(original))
            #expect(TextRenderer.image(moved, size: size, spoken: 1) === image)
        }
    }

    @Test("All drawing inputs and render variants invalidate the caption raster")
    func drawingEdits() throws {
        let original = caption()
        let image = try #require(TextRenderer.image(original, size: size, spoken: 0))
        for (key, value): (String, JSONValue) in [
            ("text", .string("Tạm biệt")), ("textPreset", .string("chapter-card")),
            ("textStyle", .object(["fill": .string("#FF0000")])), ("wordStyle", .string("reveal"))
        ] {
            var edited = original
            edited[key] = value
            #expect(TextRenderer.cacheKey(edited) != TextRenderer.cacheKey(original))
            #expect(try #require(TextRenderer.image(edited, size: size, spoken: 0)) !== image)
        }
        #expect(try #require(TextRenderer.image(original, size: size, spoken: 1)) !== image)
        #expect(try #require(TextRenderer.image(original, size: CGSize(width: 640, height: 360), spoken: 0)) !== image)
    }
}
