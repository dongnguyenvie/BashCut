import BashCutProject
import CoreGraphics
import Foundation
import Testing
@testable import BashCutEngine

/// The rendered text layout for the review (#465) matches the pixels `TextRenderer` draws.
struct TextLayoutTests {
    @Test("Layout bounds match the drawn pixels within a few pixels on long Vietnamese lines",
          arguments: ["bold-outline", "cinematic-serif", "keyword-sticker", "place-card", "chapter-card"])
    func matchesPixels(preset: String) throws {
        for size in [CGSize(width: 1080, height: 1920), CGSize(width: 1920, height: 1080)] {
            var item = Item(id: "layout", at: 0, duration: 30)
            item["text"] = .string("Hôm nay mình đi ăn phở bò ở Hà Nội, quán này ngon nhất phố cổ\nGiá chỉ 45.000 đồng")
            item["textPreset"] = .string(preset)
            item["textStyle"] = .object(["positionY": .number(0.3)])
            let layout = try #require(TextPresetStyle.layout(item, size: size))
            let raster = try #require(TextRenderer.raster(item, size: size, fullCanvas: true))
            let drawn = try #require(inkBounds(raster.bitmap))
            #expect(layout.lines == 2)
            #expect(abs(layout.minX - drawn.minX) <= 4)
            #expect(abs(layout.maxX - drawn.maxX) <= 4)
            #expect(abs(layout.minY - drawn.minY) <= 4)
            #expect(abs(layout.maxY - drawn.maxY) <= 4)
        }
    }

    @Test("Open textStyle fields (align, positionX, tracking, line height, uppercase, plate) lay out as drawn")
    func openStyle() throws {
        let size = CGSize(width: 1080, height: 1920)
        var item = Item(id: "open", at: 0, duration: 30)
        item["text"] = .string("Phở bò\nHà Nội")
        item["textPreset"] = .string("my-own-look")
        item["textStyle"] = .object([
            "align": .string("right"), "positionX": .number(0.9), "positionY": .number(0.3), "tracking": .number(0.05),
            "lineHeight": .number(1.6), "uppercase": .bool(true),
            "background": .object(["color": .string("#101010"), "opacity": .number(0.9), "radius": .number(0.3)]),
        ])
        let layout = try #require(TextPresetStyle.layout(item, size: size))
        let raster = try #require(TextRenderer.raster(item, size: size, fullCanvas: true))
        let drawn = try #require(inkBounds(raster.bitmap))
        #expect(abs(layout.maxX - drawn.maxX) <= 4 && abs(layout.minX - drawn.minX) <= 4)
        #expect(abs(layout.minY - drawn.minY) <= 4 && abs(layout.maxY - drawn.maxY) <= 4)
        #expect(layout.maxX > size.width * 0.9 - 2 && layout.maxX < size.width * 0.95)
    }

    @Test("Accent bars sit beside the block, replace the preset's bars, and the layout includes them (C1)")
    func accentBars() throws {
        let size = CGSize(width: 1920, height: 1080)
        var item = Item(id: "bars", at: 0, duration: 30)
        item["text"] = .string("Chapter one")
        item["textPreset"] = .string("place-card")
        let plain = try #require(TextPresetStyle.layout(item, size: size))
        item["textStyle"] = .object(["accentBars": .array([
            .object(["side": .string("left"), "thickness": .number(0.2), "gap": .number(0.5), "color": .string("#FF0000")]),
            .object(["side": .string("bottom"), "thickness": .number(0.1), "gap": .number(1)]),
        ])])
        let layout = try #require(TextPresetStyle.layout(item, size: size))
        let raster = try #require(TextRenderer.raster(item, size: size, fullCanvas: true))
        let drawn = try #require(inkBounds(raster.bitmap))
        #expect(abs(layout.minX - drawn.minX) <= 4 && abs(layout.minY - drawn.minY) <= 4)
        #expect(abs(layout.maxX - drawn.maxX) <= 4 && abs(layout.maxY - drawn.maxY) <= 4)
        // The place card's plate is gone; the bars reach below and left of the text.
        #expect(layout.minY < plain.minY && layout.points > 0)
        item["textStyle"] = .object(["accentBars": .array([])])
        let bare = try #require(TextPresetStyle.layout(item, size: size))
        #expect(bare.maxX - bare.minX < plain.maxX - plain.minX)
    }

    @Test("Empty text has no layout")
    func empty() {
        var item = Item(id: "empty", at: 0, duration: 30)
        item["text"] = .string("  ")
        #expect(TextPresetStyle.layout(item, size: CGSize(width: 1080, height: 1920)) == nil)
    }

    /// Bounds of the pixels with visible alpha, with y up from the bottom like the layout.
    @Test("Text templates (emphasis line, its plate, line colours) lay out as drawn, Vietnamese included",
          arguments: LibraryBuiltIns.textTemplates.map(\.id))
    func templates(id: String) throws {
        let template = try #require(LibraryBuiltIns.textTemplates.first { $0.id == id })
        for size in [CGSize(width: 1080, height: 1920), CGSize(width: 1920, height: 1080)] {
            var item = Item(id: "template", at: 0, duration: 30)
            item["text"] = .string("Hôm nay\nĂN GÌ Ở ĐÀ LẠT\ngiá bao nhiêu?")
            item["textPreset"] = template.params["textPreset"]
            // Without the shadow, ink is exactly glyphs and plates.
            var style = try #require(template.params["textStyle"]?.object)
            style["shadow"] = .bool(false)
            item["textStyle"] = .object(style)
            let layout = try #require(TextPresetStyle.layout(item, size: size))
            let raster = try #require(TextRenderer.raster(item, size: size, fullCanvas: true))
            let drawn = try #require(inkBounds(raster.bitmap))
            // Display fonts at 100+ pt: their line boxes and ink differ by up to about a sixth of the font size.
            let tolerance = max(4, layout.points * 0.17)
            #expect(layout.lines == 3)
            #expect(abs(layout.minX - drawn.minX) <= tolerance && abs(layout.maxX - drawn.maxX) <= tolerance)
            #expect(abs(layout.minY - drawn.minY) <= tolerance && abs(layout.maxY - drawn.maxY) <= tolerance)
            // Inside the frame both ways: a plate may reach past the 90% text width, not past the frame.
            #expect(layout.minX >= 0 && layout.maxX <= size.width && layout.minY >= 0 && layout.maxY <= size.height)
        }
    }

    @Test("The emphasis line is larger and in its own colour; false or a single line turns it off")
    func emphasis() throws {
        let size = CGSize(width: 1080, height: 1920)
        func height(_ text: String, _ style: [String: JSONValue]?, preset: String = "hook-title") throws -> CGFloat {
            var item = Item(id: "e", at: 0, duration: 30)
            item["text"] = .string(text)
            item["textPreset"] = .string(preset)
            var style = style ?? [:]
            style["shadow"] = .bool(false)
            item["textStyle"] = .object(style)
            let layout = try #require(TextPresetStyle.layout(item, size: size))
            return layout.maxY - layout.minY
        }
        let off = try height("ONE\nTWO", ["emphasis": .bool(false)])
        #expect(try height("ONE\nTWO", nil) > off * 1.08)
        #expect(try height("ONE\nTWO", ["emphasis": .object(["scale": .number(2)])]) > off * 1.25)
        // Other presets emphasise only when asked.
        let plain = try height("ONE\nTWO", nil, preset: "bold-outline")
        #expect(try height("ONE\nTWO", ["emphasis": .object([:])], preset: "bold-outline") > plain * 1.08)
        let single = try height("ONE", ["emphasis": .bool(false)])
        #expect(try height("ONE", nil) == single)

        var item = Item(id: "c", at: 0, duration: 30)
        item["text"] = .string("WHITE\nYELLOW")
        item["textPreset"] = .string("hook-title")
        item["textStyle"] = .object(["shadow": .bool(false), "emphasis": .bool(false),
                                     "lineFills": .array([.string("#FF0000"), .string("#0000FF")])])
        let raster = try #require(TextRenderer.raster(item, size: size, fullCanvas: true))
        let colors = inkColors(raster.bitmap)
        #expect(colors.red > 1000 && colors.blue > 1000)
    }

    /// Opaque pixels that are mostly red and mostly blue.
    private func inkColors(_ image: CGImage) -> (red: Int, blue: Int) {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var red = 0, blue = 0
        for index in stride(from: 0, to: pixels.count, by: 4) where pixels[index + 3] > 250 {
            if pixels[index] > 200 && pixels[index + 2] < 50 { red += 1 }
            if pixels[index + 2] > 200 && pixels[index] < 50 { blue += 1 }
        }
        return (red, blue)
    }

    private func inkBounds(_ image: CGImage) -> CGRect? {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var minX = width, maxX = -1, minRow = height, maxRow = -1
        for row in 0..<height {
            for column in 0..<width where pixels[(row * width + column) * 4 + 3] > 8 {
                minX = min(minX, column)
                maxX = max(maxX, column)
                minRow = min(minRow, row)
                maxRow = max(maxRow, row)
            }
        }
        guard maxX >= 0 else { return nil }
        // Memory row 0 is the top of the image.
        return CGRect(x: minX, y: height - maxRow - 1, width: maxX - minX + 1, height: maxRow - minRow + 1)
    }
}
